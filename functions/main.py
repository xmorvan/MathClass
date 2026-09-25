"""
MathClass Cloud Functions (Python)
Entry point for Firebase Cloud Functions deployed to europe-west6.

Functions:
  - extract_exercise: Extract LaTeX from exercise image using Claude Vision
  - recognize_handwriting: Recognize student handwriting from PencilKit PNG
  - correct_submission: Hybrid correction pipeline using Claude + SymPy
  - join_class / claim_student_seat: class-code login for students
    (anonymous Firebase Auth + custom claims)
  - generate_class_code: unique MX-XXXX code for a new class
  - delete_class / delete_account: cascade deletions for teachers
  - purge_old_submissions: daily deletion of submissions older than a year
"""

import firebase_admin
from firebase_functions import https_fn, options, params, scheduler_fn

# The callable wrapper verifies the caller's ID token with the default
# Admin app *before* any handler runs. Handlers import their modules lazily,
# so without this the first call on a fresh instance (e.g. join_class or
# generate_class_code) sees req.auth = None and is rejected as signed out.
if not firebase_admin._apps:
    firebase_admin.initialize_app()

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
def join_class(req: https_fn.CallableRequest) -> dict:
    """Resolve a class code into the class name and its student picker list."""
    from student_auth import join_class_handler
    return join_class_handler(req)


@https_fn.on_call()
def claim_student_seat(req: https_fn.CallableRequest) -> dict:
    """Bind the caller's anonymous account to one student of a class."""
    from student_auth import claim_student_seat_handler
    return claim_student_seat_handler(req)


@https_fn.on_call()
def generate_class_code(req: https_fn.CallableRequest) -> dict:
    """Return an MX-XXXX code no other class uses (teachers only)."""
    from student_auth import generate_class_code_handler
    return generate_class_code_handler(req)


@https_fn.on_call()
def delete_student_data(req: https_fn.CallableRequest) -> dict:
    """Hard-delete a student's PII (the student doc, all submissions, all
    Storage PNGs, levelProgress rows). Teacher-only; the function verifies
    `classes/{classID}.teacherID == auth.uid` before any delete. Used to
    satisfy GDPR / CCPA right-to-erasure for minors.
    """
    from delete_student_data import delete_student_data_handler
    return delete_student_data_handler(req)


@https_fn.on_call()
def delete_class(req: https_fn.CallableRequest) -> dict:
    """Delete one of the caller's classes and everything that belongs to it."""
    from data_deletion import delete_class_handler
    return delete_class_handler(req)


@https_fn.on_call()
def delete_account(req: https_fn.CallableRequest) -> dict:
    """Delete the calling teacher's account and all their data."""
    from data_deletion import delete_account_handler
    return delete_account_handler(req)


@scheduler_fn.on_schedule(schedule="every day 03:00", timezone=scheduler_fn.Timezone("Europe/Zurich"))
def purge_old_submissions(event: scheduler_fn.ScheduledEvent) -> None:
    """Delete submissions and handwriting images older than the retention period."""
    from data_deletion import purge_old_submissions as purge
    deleted = purge()
    print(f"[purge_old_submissions] deleted {deleted} submissions")
