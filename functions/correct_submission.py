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

import anthropic
from firebase_functions import https_fn

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
            return {
                "stepResults": [False] * len(student_steps),
                "firstErrorIndex": 0,
                "allCorrect": False,
            }

        # Phase 2: Verify each step pair
        step_results = []
        first_error_index = None

        for i, pair in enumerate(pairs):
            student_expr = pair.get("studentExpr", "")
            reference_expr = pair.get("referenceExpr", "")
            description = pair.get("description", "")

            # Try SymPy first
            sympy_result = sympy_check_equivalence(student_expr, reference_expr)

            if sympy_result is not None:
                # SymPy could determine the result
                is_correct = sympy_result
            else:
                # Fallback to Claude
                is_correct = claude_check_equivalence(
                    client, student_expr, reference_expr, description
                )

            step_results.append(is_correct)

            if not is_correct and first_error_index is None:
                first_error_index = i

        all_correct = all(step_results)

        # Persist the correction result on the submission doc using the
        # Admin SDK so it bypasses firestore.rules (the rule on submissions
        # update is `isTeacher()`, and students have no Firebase Auth —
        # the previous client-side write silently failed; see ISSUE-040).
        if all_correct:
            final_result = "success_1st" if attempt_number == 1 else "success_2nd"
        else:
            final_result = "failed"

        try:
            db = _get_firestore()
            db.collection("submissions").document(submission_id).update({
                "correctionResult": {
                    "stepResults": step_results,
                    "firstErrorIndex": first_error_index,
                },
                "finalResult": final_result,
            })
        except Exception as persist_error:
            # Do not fail the whole call — the iOS client already has the
            # correction in memory and can render feedback. The teacher
            # inbox just won't see this submission until the next manual
            # retry. Log and continue.
            print(f"[correct_submission] Firestore persist failed: {persist_error}")

        return {
            "stepResults": step_results,
            "firstErrorIndex": first_error_index,
            "allCorrect": all_correct,
        }

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
