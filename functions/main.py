"""
MathClass Cloud Functions (Python)
Entry point for Firebase Cloud Functions deployed to europe-west6.

Functions:
  - extract_exercise: Extract LaTeX from exercise image using Claude Haiku 4.5 Vision
  - recognize_handwriting: Recognize student handwriting from PencilKit PNG
  - correct_submission: Hybrid correction pipeline using Claude + SymPy
"""

from firebase_functions import https_fn, options

# Set region for all functions
options.set_global_options(region=options.SupportedRegion.EUROPE_WEST6)

# Import function implementations
from extract_exercise import extract_exercise_handler
from recognize_handwriting import recognize_handwriting_handler
from correct_submission import correct_submission_handler


@https_fn.on_call()
def extract_exercise(req: https_fn.CallableRequest) -> dict:
    """Extract LaTeX statement and expected answer from an exercise image.

    Args:
        req.data["storagePath"]: Cloud Storage path to the exercise image.

    Returns:
        dict with "statement" (LaTeX/text) and "expectedAnswer" (LaTeX).
    """
    return extract_exercise_handler(req)


@https_fn.on_call()
def recognize_handwriting(req: https_fn.CallableRequest) -> dict:
    """Recognize student handwriting from a PencilKit PNG export.

    Args:
        req.data["storagePath"]: Cloud Storage path to the PNG, OR
        req.data["imageBase64"]: Base64-encoded PNG image.
        req.data["format"]: Image format (default: "png").

    Returns:
        dict with "steps" (list of LaTeX strings) and "confidence" (float 0-1).
    """
    return recognize_handwriting_handler(req)


@https_fn.on_call()
def correct_submission(req: https_fn.CallableRequest) -> dict:
    """Correct a student's submission using hybrid Claude + SymPy pipeline.

    Args:
        req.data["studentSteps"]: List of LaTeX strings (student's work).
        req.data["expectedAnswer"]: LaTeX string (correct answer).
        req.data["statement"]: Exercise statement for context.

    Returns:
        dict with "stepResults" (list of booleans), "firstErrorIndex" (int or null),
        and "allCorrect" (boolean).
    """
    return correct_submission_handler(req)
