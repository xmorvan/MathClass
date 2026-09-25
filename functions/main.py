"""
MathClass Cloud Functions (Python)
Entry point for Firebase Cloud Functions deployed to europe-west6.

Functions:
  - extract_exercise: Extract LaTeX from exercise image using Claude Haiku 4.5 Vision
  - recognize_handwriting: Recognize student handwriting from PencilKit PNG
  - correct_submission: Hybrid correction pipeline using Claude + SymPy
"""

from firebase_functions import https_fn, options, params

# Set region for all functions
options.set_global_options(region=options.SupportedRegion.EUROPE_WEST6)

# Anthropic API key sourced from Firebase Secret Manager rather than a plain
# env var (ISSUE-014). Set it once with:
#   firebase functions:secrets:set ANTHROPIC_API_KEY
# The decorator binding below makes the secret available inside each handler
# as `os.environ["ANTHROPIC_API_KEY"]`, so the per-handler implementations
# don't need to know about SecretParam.
# The Firebase Functions Python SDK's local discovery server re-execs
# `main.py` on every request to `/__/functions.yaml`. Without this guard,
# the second declaration of the SecretParam raises
# `ValueError: Duplicate Parameter Error`, which surfaces during
# `firebase deploy` as a hung "Loading and analyzing source code" step.
try:
    ANTHROPIC_KEY = params.SecretParam("ANTHROPIC_API_KEY")
except ValueError:
    ANTHROPIC_KEY = params._params["ANTHROPIC_API_KEY"]  # noqa: SLF001

# Handler modules are imported lazily inside each function — the top-level
# imports of anthropic, firebase_admin, sympy, etc. are collectively too
# heavy and blow the 10-second deployment introspection timeout.


@https_fn.on_call(secrets=[ANTHROPIC_KEY])
def extract_exercise(req: https_fn.CallableRequest) -> dict:
    """Extract LaTeX statement and expected answer from an exercise image."""
    from extract_exercise import extract_exercise_handler
    return extract_exercise_handler(req)


@https_fn.on_call(secrets=[ANTHROPIC_KEY])
def recognize_handwriting(req: https_fn.CallableRequest) -> dict:
    """Recognize student handwriting from a PencilKit PNG export."""
    from recognize_handwriting import recognize_handwriting_handler
    return recognize_handwriting_handler(req)


@https_fn.on_call(secrets=[ANTHROPIC_KEY])
def correct_submission(req: https_fn.CallableRequest) -> dict:
    """Correct a student's submission using hybrid Claude + SymPy pipeline."""
    from correct_submission import correct_submission_handler
    return correct_submission_handler(req)


@https_fn.on_call()
def link_student_session(req: https_fn.CallableRequest) -> dict:
    """Bind an anonymous Firebase Auth UID to a (classID, studentID) pair
    via custom claims. Required so subsequent Firestore / Storage / callable
    requests carry `request.auth.token.studentID` for the security rules and
    server-side ownership checks. See link_student_session.py for the flow.
    """
    from link_student_session import link_student_session_handler
    return link_student_session_handler(req)


@https_fn.on_call()
def delete_student_data(req: https_fn.CallableRequest) -> dict:
    """Hard-delete a student's PII (the student doc, all submissions, all
    Storage PNGs, levelProgress rows). Teacher-only; the function verifies
    `classes/{classID}.teacherID == auth.uid` before any delete. Used to
    satisfy GDPR / CCPA right-to-erasure for minors.
    """
    from delete_student_data import delete_student_data_handler
    return delete_student_data_handler(req)
