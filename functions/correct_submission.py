"""
correct_submission.py
Cloud Function that implements the hybrid correction pipeline.

Correction process:
1. Receive student LaTeX steps + expected answer + exercise statement
2. Claude Haiku structures step pairs (student_expression, reference_expression)
3. SymPy verifies algebraic equivalence for each pair: simplify(student - ref) == 0
4. If SymPy can't determine → Claude fallback judgment
5. Return CorrectionResult: {stepResults: [true, true, false], firstErrorIndex: 2}
"""

import json
import os
import re
import time

import anthropic
from firebase_functions import https_fn

import auth_guard

# SymPy is imported lazily on first call — `import sympy` alone takes
# several seconds and blows the 10-second Cloud Functions deployment
# introspection timeout when combined with the other heavy imports
# (anthropic, firebase_functions, etc.).
sympy = None
parse_latex = None
SYMPY_AVAILABLE = False


def _ensure_sympy():
    """Lazy-load sympy + parse_latex on first use."""
    global sympy, parse_latex, SYMPY_AVAILABLE
    if sympy is not None:
        return
    try:
        import sympy as _sympy
        from sympy.parsing.latex import parse_latex as _parse_latex

        # parse_latex needs antlr4-python3-runtime, but a missing antlr does
        # not raise on import — it raises the first time parse_latex runs.
        # Probe here so SYMPY_AVAILABLE reflects actual usability.
        _parse_latex("1+1")

        sympy = _sympy
        parse_latex = _parse_latex
        SYMPY_AVAILABLE = True
    except Exception:
        SYMPY_AVAILABLE = False


def _get_firestore():
    """Lazy-load firebase_admin.firestore() — kept off the import path so the
    deployment introspection step doesn't pay for it. Initialises the default
    app if no other handler did so first."""
    import firebase_admin
    from firebase_admin import firestore

    if not firebase_admin._apps:
        firebase_admin.initialize_app()
    return firestore.client()


# System prompt for structuring step pairs (Phase 1 of correction)
STRUCTURING_PROMPT = """Tu es un correcteur mathématique expert. Tu dois vérifier le travail d'un élève étape par étape.

Exercice :
{statement}

Réponse attendue : {expected_answer}

Travail de l'élève (étapes LaTeX) :
{student_steps}

Ta tâche :
1. Pour chaque étape de l'élève, détermine l'expression mathématique de référence correspondante
   (ce que l'étape DEVRAIT être si elle est correcte dans le contexte du raisonnement)
2. La dernière étape doit aboutir à la réponse attendue

Réponds UNIQUEMENT avec un JSON valide, sans markdown ni backticks :
{{
  "pairs": [
    {{
      "studentExpr": "expression LaTeX de l'élève",
      "referenceExpr": "expression LaTeX de référence correcte",
      "description": "brève description de ce que cette étape fait"
    }},
    ...
  ]
}}

Si le travail de l'élève est vide ou incompréhensible :
{{
  "pairs": []
}}
"""

# System prompt for Claude fallback verification (when SymPy can't decide)
FALLBACK_PROMPT = """Tu es un vérificateur mathématique. Compare ces deux expressions et détermine si elles sont mathématiquement équivalentes.

Expression de l'élève : {student_expr}
Expression de référence : {reference_expr}
Contexte : {description}

Réponds UNIQUEMENT avec un JSON valide :
{{
  "equivalent": true ou false,
  "reason": "brève explication"
}}
"""


def sympy_check_equivalence(student_latex: str, reference_latex: str) -> bool | None:
    """Check algebraic equivalence using SymPy.

    Returns:
        True if equivalent, False if not, None if SymPy can't determine.
    """
    _ensure_sympy()
    if not SYMPY_AVAILABLE:
        return None

    try:
        student_expr = parse_latex(student_latex)
        reference_expr = parse_latex(reference_latex)

        # Try direct simplification
        diff = sympy.simplify(student_expr - reference_expr)
        if diff == 0:
            return True

        # Try expanding then simplifying
        diff_expanded = sympy.simplify(sympy.expand(student_expr) - sympy.expand(reference_expr))
        if diff_expanded == 0:
            return True

        # Try trigonometric simplification
        diff_trig = sympy.trigsimp(student_expr - reference_expr)
        if diff_trig == 0:
            return True

        # If simplification gives a non-zero constant, they're definitely not equal
        if diff.is_number and diff != 0:
            return False

        # SymPy can't determine — return None for Claude fallback
        return None

    except Exception:
        # Parse error or unsupported expression — fallback to Claude
        return None


def claude_check_equivalence(
    client: anthropic.Anthropic,
    student_expr: str,
    reference_expr: str,
    description: str,
) -> bool:
    """Fallback equivalence check using Claude when SymPy can't determine.

    Returns:
        True if Claude considers the expressions equivalent, False otherwise.
    """
    prompt = FALLBACK_PROMPT.format(
        student_expr=student_expr,
        reference_expr=reference_expr,
        description=description,
    )

    message = client.messages.create(
        # Claude Haiku 4.5 — see extract_exercise.py for the rationale
        # on the date suffix.
        model="claude-haiku-4-5-20251001",
        max_tokens=256,
        messages=[{"role": "user", "content": prompt}],
    )

    response_text = message.content[0].text.strip()

    try:
        result = json.loads(response_text)
        return result.get("equivalent", False)
    except json.JSONDecodeError:
        json_match = re.search(r"\{.*\}", response_text, re.DOTALL)
        if json_match:
            result = json.loads(json_match.group())
            return result.get("equivalent", False)
        return False


NOTATION_PROMPT = """Tu es un correcteur mathématique vétilleux sur la notation, mais juste sur le fond. Examine ces étapes d'élève :

Énoncé : {statement}
Étapes :
{steps}

Indique UNIQUEMENT les problèmes de NOTATION (parenthèses manquantes autour d'un négatif, points de multiplication implicites ambigus, mélange virgule/point décimal, écriture x*x au lieu de x^2, etc.).
NE COMMENTE PAS la justesse mathématique — uniquement la forme.

Réponds UNIQUEMENT en JSON :
{{
  "hasIssue": true ou false,
  "note": "phrase courte décrivant le problème de notation, sans corriger le fond"
}}

Si tu ne vois aucun problème de notation, mets hasIssue=false et note="".
"""


def _detect_notation_issue(
    client: anthropic.Anthropic,
    student_steps: list,
    statement: str,
) -> str | None:
    """Run a Claude pass that flags notation problems separately from
    algebraic correctness. Returns the note or None.

    Errors are swallowed — notation feedback is best-effort.
    """
    try:
        formatted = "\n".join([f"Étape {i + 1}: {s}" for i, s in enumerate(student_steps)])
        prompt = NOTATION_PROMPT.format(statement=statement or "(sans énoncé)", steps=formatted)
        message = client.messages.create(
            model="claude-haiku-4-5-20251001",
            max_tokens=256,
            messages=[{"role": "user", "content": prompt}],
        )
        text = message.content[0].text.strip()
        try:
            data = json.loads(text)
        except json.JSONDecodeError:
            json_match = re.search(r"\{.*\}", text, re.DOTALL)
            if not json_match:
                return None
            data = json.loads(json_match.group())
        if not data.get("hasIssue"):
            return None
        note = (data.get("note") or "").strip()
        return note if note else None
    except Exception as exc:
        print(f"[correct_submission] notation pass failed: {exc}")
        return None


CLASSIFY_PROMPT = """Catégorise chaque étape ci-dessous parmi : "sign_error", "arithmetic", "algebra", "notation", "conceptual", ou null si l'étape est correcte ou inclassable.

Étapes (avec verdict) :
{lines}

Réponds UNIQUEMENT en JSON :
{{
  "tags": ["sign_error", null, "algebra"]
}}
"""


def _classify_errors(
    client: anthropic.Anthropic,
    student_steps: list,
    step_results: list,
) -> list:
    """Per-step error category. Returns a list of length len(student_steps)
    with each entry being a short tag string or None. Best-effort.
    """
    n = len(student_steps)
    try:
        lines = []
        for i in range(n):
            verdict = "OK" if (i < len(step_results) and step_results[i]) else "ERREUR"
            lines.append(f"Étape {i + 1} ({verdict}): {student_steps[i]}")
        prompt = CLASSIFY_PROMPT.format(lines="\n".join(lines))
        message = client.messages.create(
            model="claude-haiku-4-5-20251001",
            max_tokens=256,
            messages=[{"role": "user", "content": prompt}],
        )
        text = message.content[0].text.strip()
        try:
            data = json.loads(text)
        except json.JSONDecodeError:
            json_match = re.search(r"\{.*\}", text, re.DOTALL)
            if not json_match:
                return [None] * n
            data = json.loads(json_match.group())
        tags = data.get("tags") or []
        # Pad / truncate to length n.
        if len(tags) < n:
            tags = tags + [None] * (n - len(tags))
        elif len(tags) > n:
            tags = tags[:n]
        # Normalize: keep strings and None only.
        normalized: list = []
        for t in tags:
            if isinstance(t, str) and t.strip():
                normalized.append(t.strip())
            else:
                normalized.append(None)
        return normalized
    except Exception as exc:
        print(f"[correct_submission] classification pass failed: {exc}")
        return [None] * n


def _persist_correction(
    submission_id: str,
    step_results: list[bool],
    first_error_index: int | None,
    final_result: str,
    notation_note: str | None = None,
    error_tags: list | None = None,
) -> Exception | None:
    """Write the correction result to /submissions/{id} via Admin SDK.

    Retries up to 3 times with short backoff. Returns None on success, or
    the last raised exception so the caller can decide whether to surface
    a failure to the client (ISSUE-004).
    """
    last_error: Exception | None = None
    for attempt in range(3):
        try:
            db = _get_firestore()
            doc: dict = {
                "correctionResult": {
                    "stepResults": step_results,
                    "firstErrorIndex": first_error_index,
                },
                "finalResult": final_result,
            }
            if notation_note is not None:
                doc["correctionResult"]["notationNote"] = notation_note
            if error_tags is not None:
                doc["correctionResult"]["errorTags"] = error_tags
            db.collection("submissions").document(submission_id).update(doc)
            return None
        except Exception as e:  # noqa: BLE001 — retry any failure
            last_error = e
            print(
                f"[correct_submission] Firestore persist attempt "
                f"{attempt + 1}/3 failed for {submission_id}: {e}"
            )
            time.sleep(0.4 * (attempt + 1))
    return last_error


def _authorize(req: https_fn.CallableRequest, submission_id: str) -> dict:
    """Check that the calling student owns the submission.

    Returns the grading context read from Firestore (expected answer,
    statement, notation strictness) so the client cannot change what it
    is graded against.
    """
    identity = auth_guard.require_student(req)
    db = _get_firestore()

    submission = db.collection("submissions").document(submission_id).get()
    if not submission.exists:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.NOT_FOUND,
            message="Soumission introuvable.",
        )
    submission_data = submission.to_dict() or {}
    if submission_data.get("studentID") != identity.student_id:
        raise auth_guard._denied()

    exercise_id = submission_data.get("exerciseID")
    exercise = (
        db.collection("exercises").document(exercise_id).get()
        if isinstance(exercise_id, str) and exercise_id
        else None
    )
    if exercise is None or not exercise.exists:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.NOT_FOUND,
            message="Exercice introuvable.",
        )
    exercise_data = exercise.to_dict() or {}

    class_doc = db.collection("classes").document(identity.class_id).get()
    class_data = (class_doc.to_dict() or {}) if class_doc.exists else {}
    notation_strict = class_data.get("notationStrict")

    return {
        "expected_answer": exercise_data.get("expectedAnswer", ""),
        "statement": exercise_data.get("statement", ""),
        # Legacy classes without the field default to strict.
        "notation_strict": True if notation_strict is None else bool(notation_strict),
    }


def correct_submission_handler(req: https_fn.CallableRequest) -> dict:
    """Handle the correct_submission Cloud Function call.

    Args:
        req.data:
            - studentSteps: list of LaTeX strings (student's work)
            - submissionID: Firestore document ID — the function will patch
              correctionResult + finalResult on this doc via Admin SDK.
              The caller must be the student who owns it (custom claims);
              the rules forbid clients from writing correction results.
            - expectedAnswer / statement / notationStrict: ignored. They are
              read from the exercise and class documents instead.
            - attemptNumber: 1 or 2 (used to compute success_1st vs success_2nd).

    Returns:
        dict with:
            - stepResults: list of booleans (true = correct per step)
            - firstErrorIndex: int or null (index of first wrong step)
            - allCorrect: boolean (shortcut)

    Raises:
        https_fn.HttpsError on validation or processing failures.
    """
    if not req.data:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="Aucune donnée fournie.",
        )

    student_steps = req.data.get("studentSteps", [])
    submission_id = req.data.get("submissionID")
    attempt_number = req.data.get("attemptNumber")

    if not isinstance(student_steps, list):
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="'studentSteps' doit être une liste.",
        )

    # Bound the input — a runaway list would burn Anthropic credits and
    # blow the 60s function timeout (ISSUE-013).
    if len(student_steps) > 30:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="Trop d'étapes (maximum 30).",
        )

    if not isinstance(submission_id, str) or not submission_id:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="'submissionID' est requis.",
        )

    if attempt_number not in (1, 2):
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="'attemptNumber' doit être 1 ou 2.",
        )

    # Grade against the exercise stored in Firestore, not against whatever
    # expected answer the client sent.
    context = _authorize(req, submission_id)
    expected_answer = context["expected_answer"]
    statement = context["statement"]
    notation_strict = context["notation_strict"]

    if not student_steps:
        return {
            "stepResults": [],
            "firstErrorIndex": None,
            "allCorrect": False,
        }

    # Get Anthropic API key
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message="Clé API Anthropic non configurée.",
        )

    try:
        client = anthropic.Anthropic(api_key=api_key)

        # Phase 1: Use Claude to structure step pairs
        formatted_steps = "\n".join(
            [f"Étape {i + 1}: {step}" for i, step in enumerate(student_steps)]
        )

        structuring_prompt = STRUCTURING_PROMPT.format(
            statement=statement,
            expected_answer=expected_answer,
            student_steps=formatted_steps,
        )

        message = client.messages.create(
            # Claude Haiku 4.5 — see extract_exercise.py for the rationale
            # on the date suffix.
            model="claude-haiku-4-5-20251001",
            max_tokens=2048,
            messages=[{"role": "user", "content": structuring_prompt}],
        )

        response_text = message.content[0].text.strip()

        try:
            structured = json.loads(response_text)
        except json.JSONDecodeError:
            json_match = re.search(r"\{.*\}", response_text, re.DOTALL)
            if json_match:
                structured = json.loads(json_match.group())
            else:
                raise https_fn.HttpsError(
                    code=https_fn.FunctionsErrorCode.INTERNAL,
                    message="Impossible de parser la structuration des étapes.",
                )

        pairs = structured.get("pairs", [])

        if not pairs:
            # Claude couldn't structure the steps — all marked as incorrect
            step_results = [False] * len(student_steps)
            first_error_index = 0
            all_correct = False
        else:
            # Phase 2: Verify each step pair.
            # ISSUE-006: Claude can return fewer pairs than studentSteps. Pair
            # by index up to the shorter list and treat any unpaired tail as
            # "could not verify" → False (counts as wrong, conservative). This
            # keeps len(stepResults) == len(studentSteps), which the iOS
            # client relies on when rendering per-step marks.
            step_results: list[bool] = []
            first_error_index: int | None = None

            paired_count = min(len(pairs), len(student_steps))
            for i in range(paired_count):
                pair = pairs[i]
                student_expr = pair.get("studentExpr", "")
                reference_expr = pair.get("referenceExpr", "")
                description = pair.get("description", "")

                sympy_result = sympy_check_equivalence(student_expr, reference_expr)

                if sympy_result is not None:
                    is_correct = sympy_result
                else:
                    is_correct = claude_check_equivalence(
                        client, student_expr, reference_expr, description
                    )

                step_results.append(is_correct)
                if not is_correct and first_error_index is None:
                    first_error_index = i

            # Pad any unpaired tail as wrong + log so the mismatch is visible.
            if paired_count < len(student_steps):
                missing = len(student_steps) - paired_count
                print(
                    f"[correct_submission] Phase-1 pair shortfall: "
                    f"{paired_count} pairs vs {len(student_steps)} student steps "
                    f"(padding {missing} as incorrect)"
                )
                for i in range(paired_count, len(student_steps)):
                    step_results.append(False)
                    if first_error_index is None:
                        first_error_index = i

            all_correct = all(step_results)

        # Persist the correction result on the submission doc using the
        # Admin SDK so it bypasses firestore.rules (the rule on submissions
        # update is `isTeacher()`, and students have no Firebase Auth).
        if all_correct:
            final_result = "success_1st" if attempt_number == 1 else "success_2nd"
        else:
            final_result = "failed"

        # Notation pass: when the class has notationStrict=True, ask Claude
        # to flag any notation problem found in the steps WITHOUT flipping
        # the verdict. The note is rendered as a separate banner in the
        # student's feedback view. Skipped entirely when notationStrict is
        # false to save Anthropic credits.
        notation_note: str | None = None
        if notation_strict and student_steps:
            notation_note = _detect_notation_issue(
                client, student_steps, statement
            )

        # Per-step error categorization (sign / arithmetic / notation /
        # conceptual). Only run for failed steps so we don't pay for it
        # when everything is correct.
        error_tags: list | None = None
        if not all_correct and pairs:
            error_tags = _classify_errors(
                client, student_steps, step_results
            )

        # ISSUE-004: previously a persist failure was logged and swallowed,
        # so the teacher's inbox would never see a submission whose write
        # had failed. Now we retry a few times and then surface the failure
        # to the iOS client via HttpsError so it can prompt the student to
        # retry submission. The in-memory result is still returned on
        # success, so the student gets feedback on the happy path.
        persist_error = _persist_correction(
            submission_id=submission_id,
            step_results=step_results,
            first_error_index=first_error_index,
            final_result=final_result,
            notation_note=notation_note,
            error_tags=error_tags,
        )
        if persist_error is not None:
            raise https_fn.HttpsError(
                code=https_fn.FunctionsErrorCode.UNAVAILABLE,
                message=(
                    "La correction a réussi mais l'enregistrement a échoué. "
                    "Réessayez dans quelques instants."
                ),
                details={"reason": str(persist_error)},
            )

        response: dict = {
            "stepResults": step_results,
            "firstErrorIndex": first_error_index,
            "allCorrect": all_correct,
        }
        if notation_note is not None:
            response["notationNote"] = notation_note
        if error_tags is not None:
            response["errorTags"] = error_tags
        return response

    except https_fn.HttpsError:
        raise
    except anthropic.APIError as e:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message=f"Erreur API Anthropic: {str(e)}",
        )
    except Exception as e:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message=f"Erreur lors de la correction: {str(e)}",
        )
