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
import time
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeoutError

import anthropic
from firebase_functions import https_fn

from _helpers import extract_json, make_anthropic_client

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


def _caller_student_id(req: https_fn.CallableRequest) -> str | None:
    """Extract the `studentID` custom claim from the callable's auth context,
    or None if the caller didn't sign in via `link_student_session`. Defensive
    against test stubs that don't set `req.auth` at all (the production
    runtime always sets it; tests use SimpleNamespace).
    """
    auth = getattr(req, "auth", None)
    if auth is None:
        return None
    token = getattr(auth, "token", None)
    if not isinstance(token, dict):
        return None
    sid = token.get("studentID")
    return sid if isinstance(sid, str) and sid else None


# System prompt for structuring step pairs (Phase 1 of correction). The
# rules block is static so it can be cached server-side by Anthropic; the
# per-call statement / expected_answer / student_steps go in the user
# message. Switching to system+cache cut the structuring-prompt input
# tokens by ~80 % on warm cache (see ISSUE-014).
STRUCTURING_SYSTEM = """Tu es un correcteur mathématique expert. Tu dois vérifier le travail d'un élève étape par étape.

Ta tâche :
1. Pour chaque étape de l'élève, détermine l'expression mathématique de référence correspondante
   (ce que l'étape DEVRAIT être si elle est correcte dans le contexte du raisonnement).
2. La dernière étape doit aboutir à la réponse attendue.

Réponds UNIQUEMENT avec un JSON valide, sans markdown ni backticks :
{
  "pairs": [
    {
      "studentExpr": "expression LaTeX de l'élève",
      "referenceExpr": "expression LaTeX de référence correcte",
      "description": "brève description de ce que cette étape fait"
    }
  ]
}

Si le travail de l'élève est vide ou incompréhensible :
{
  "pairs": []
}
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


def _run_with_timeout(fn, *args, secs: float = 3.0, **kwargs):
    """Run a SymPy call in a worker thread, raising FutureTimeoutError if it
    runs longer than `secs`. SymPy has no native timeout API and pathological
    expressions (deeply nested radicals, very large polynomials) can simplify
    for minutes — long enough to eat the entire Cloud Functions wall clock.

    SIGALRM would be simpler but isn't safe under Cloud Run (multi-threaded);
    a worker thread is portable.
    """
    with ThreadPoolExecutor(max_workers=1) as pool:
        future = pool.submit(fn, *args, **kwargs)
        return future.result(timeout=secs)


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

        # Try direct simplification (timeout-bounded).
        diff = _run_with_timeout(sympy.simplify, student_expr - reference_expr)
        if diff == 0:
            return True

        # Try expanding then simplifying.
        expanded_diff = sympy.expand(student_expr) - sympy.expand(reference_expr)
        diff_expanded = _run_with_timeout(sympy.simplify, expanded_diff)
        if diff_expanded == 0:
            return True

        # Try trigonometric simplification.
        diff_trig = _run_with_timeout(sympy.trigsimp, student_expr - reference_expr)
        if diff_trig == 0:
            return True

        # If simplification gives a non-zero constant, they're definitely not equal
        if diff.is_number and diff != 0:
            return False

        # SymPy can't determine — return None for Claude fallback
        return None

    except FutureTimeoutError:
        # SymPy ran past the per-call budget — treat as undecidable so the
        # Claude fallback takes over. Logged so the slow expression is visible
        # in Cloud Logging if it recurs.
        print(
            f"[sympy] simplify timed out after 3s; "
            f"student={student_latex[:80]!r} reference={reference_latex[:80]!r}"
        )
        return None
    except Exception as exc:
        # Parse error, missing antlr, or unsupported expression — fall back to
        # Claude. Logging so a missing antlr at deploy time is visible (without
        # this, every step paid for an extra Claude round-trip silently).
        print(f"[sympy] check failed: {exc}")
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

    try:
        result = extract_json(message.content[0].text)
        return bool(result.get("equivalent", False))
    except json.JSONDecodeError:
        return False


# Fixed taxonomy of notation issues. The Cloud Function returns a key from
# this set (or null) so the iOS client can localize it; this used to be a
# free-form French phrase, which the iOS client rendered raw and broke the
# bilingual mandate (ISSUE-014).
NOTATION_KEYS = {
    "missing_brackets",       # negatives without parentheses, e.g. -x written as -x in 2*-x
    "decimal_separator",      # comma vs period (3,14 vs 3.14)
    "implicit_multiplication", # 2x ambiguous, missing \cdot
    "missing_unit",           # numeric answer with no unit when expected
    "ambiguous_fraction",     # 1/2x — is it (1/2)x or 1/(2x)?
    "power_notation",         # x*x written as xx instead of x^2
}

NOTATION_SYSTEM = """Tu es un correcteur mathématique vétilleux sur la notation, mais juste sur le fond.

Ta tâche : examiner les étapes de l'élève et détecter UN problème de notation parmi cette liste fermée :
- "missing_brackets" : un signe négatif sans parenthèses, par ex. 2*-3 au lieu de 2*(-3).
- "decimal_separator" : virgule et point mélangés ou utilisés contre la convention.
- "implicit_multiplication" : multiplication implicite ambiguë (2x au lieu de 2·x quand le contexte l'exige).
- "missing_unit" : réponse numérique sans unité quand une est attendue.
- "ambiguous_fraction" : fraction écrite 1/2x sans parenthèses.
- "power_notation" : x*x écrit au lieu de x^2 (ou similaire).

NE COMMENTE PAS la justesse mathématique — uniquement la forme.

Réponds UNIQUEMENT en JSON, sans markdown :
{
  "key": "missing_brackets" | "decimal_separator" | "implicit_multiplication" | "missing_unit" | "ambiguous_fraction" | "power_notation" | null
}

Si tu ne vois aucun problème de notation, retourne {"key": null}.
"""


def _detect_notation_issue(
    client: anthropic.Anthropic,
    student_steps: list,
    statement: str,
) -> str | None:
    """Run a Claude pass that flags notation problems separately from
    algebraic correctness. Returns one of the NOTATION_KEYS or None.

    The key is language-neutral — the iOS client looks up a localized
    string in `Localizations.swift` keyed on `notation_note_<key>`.
    Errors are swallowed — notation feedback is best-effort.
    """
    try:
        formatted = "\n".join([f"Étape {i + 1}: {s}" for i, s in enumerate(student_steps)])
        user = f"Énoncé : {statement or '(sans énoncé)'}\nÉtapes :\n{formatted}"
        message = client.messages.create(
            model="claude-haiku-4-5-20251001",
            max_tokens=64,
            system=[
                {
                    "type": "text",
                    "text": NOTATION_SYSTEM,
                    "cache_control": {"type": "ephemeral"},
                }
            ],
            messages=[{"role": "user", "content": user}],
        )
        try:
            data = extract_json(message.content[0].text)
        except json.JSONDecodeError:
            return None
        key = data.get("key")
        if not isinstance(key, str) or key not in NOTATION_KEYS:
            return None
        return key
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
        try:
            data = extract_json(message.content[0].text)
        except json.JSONDecodeError:
            return [None] * n
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
    notation_note_key: str | None = None,
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
            if notation_note_key is not None:
                doc["correctionResult"]["notationNoteKey"] = notation_note_key
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


def correct_submission_handler(req: https_fn.CallableRequest) -> dict:
    """Handle the correct_submission Cloud Function call.

    Args:
        req.data:
            - studentSteps: list of LaTeX strings (student's work)
            - expectedAnswer: LaTeX string (the correct answer)
            - statement: Exercise statement for context
            - submissionID: Firestore document ID — the function will patch
              correctionResult + finalResult on this doc via Admin SDK.
              Required because students have no Firebase Auth and the
              firestore.rules update guard is `isTeacher()`; the client
              cannot persist correction results itself.
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
    expected_answer = req.data.get("expectedAnswer", "")
    statement = req.data.get("statement", "")
    submission_id = req.data.get("submissionID")
    attempt_number = req.data.get("attemptNumber")
    # New: class-level notation strictness (default True). When True the
    # function flags notation issues separately without flipping the
    # verdict; when False notation is ignored entirely.
    notation_strict = bool(req.data.get("notationStrict", True))

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

    # Ownership check (ISSUE-014). The Admin SDK persist later in this
    # function bypasses Firestore rules, so the function itself has to
    # confirm the caller actually owns the submission they're patching.
    # The `studentID` claim is set by `link_student_session` on the iPad's
    # anonymous Firebase Auth UID; without it, no submission is ours.
    caller_student_id = _caller_student_id(req)
    if not caller_student_id:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.UNAUTHENTICATED,
            message="Session élève manquante. Reconnectez-vous.",
        )

    db = _get_firestore()
    submission_ref = db.collection("submissions").document(submission_id)
    submission_snap = submission_ref.get()
    if not submission_snap.exists:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.NOT_FOUND,
            message="Soumission introuvable.",
        )
    submission_owner = (submission_snap.to_dict() or {}).get("studentID")
    if submission_owner != caller_student_id:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.PERMISSION_DENIED,
            message="Cette soumission ne vous appartient pas.",
        )

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
        client = make_anthropic_client(api_key)

        # Phase 1: Use Claude to structure step pairs
        formatted_steps = "\n".join(
            [f"Étape {i + 1}: {step}" for i, step in enumerate(student_steps)]
        )

        # Cache the static prefix of the structuring prompt — the only
        # per-call dynamic parts are the statement, expected answer, and
        # the student's steps. Sending the rules block as a cache-eligible
        # system message cuts ~80 % of the input tokens on warm cache.
        structuring_user = (
            f"Exercice :\n{statement}\n\n"
            f"Réponse attendue : {expected_answer}\n\n"
            f"Travail de l'élève (étapes LaTeX) :\n{formatted_steps}"
        )

        message = client.messages.create(
            # Claude Haiku 4.5 — see extract_exercise.py for the rationale
            # on the date suffix.
            model="claude-haiku-4-5-20251001",
            max_tokens=2048,
            system=[
                {
                    "type": "text",
                    "text": STRUCTURING_SYSTEM,
                    "cache_control": {"type": "ephemeral"},
                }
            ],
            messages=[{"role": "user", "content": structuring_user}],
        )

        try:
            structured = extract_json(message.content[0].text)
        except json.JSONDecodeError:
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
        # the verdict. The returned value is a language-neutral key (one of
        # NOTATION_KEYS) — the iOS client maps it through Localizations.swift
        # to a localized banner. Skipped entirely when notationStrict is
        # false to save Anthropic credits.
        notation_note_key: str | None = None
        if notation_strict and student_steps:
            notation_note_key = _detect_notation_issue(
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
            notation_note_key=notation_note_key,
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
        if notation_note_key is not None:
            response["notationNoteKey"] = notation_note_key
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
