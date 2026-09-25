"""
auth_guard.py
Caller authorization shared by every callable Cloud Function.

Two kinds of callers exist:
  - Teachers: Firebase Auth email/password accounts with a
    `users/{uid}` profile whose `role` is "teacher".
  - Students: Firebase Auth *anonymous* accounts. They get the custom
    claims {role: "student", classID, studentID} from
    `claim_student_seat` once they have entered a valid class code and
    picked their name. Firestore/Storage rules and the functions below
    trust those claims, never client-supplied IDs.
"""

from __future__ import annotations

from dataclasses import dataclass

from firebase_functions import https_fn


@dataclass(frozen=True)
class StudentIdentity:
    uid: str
    class_id: str
    student_id: str


def _get_firestore():
    """Lazy Admin SDK Firestore client (kept off the deploy import path)."""
    import firebase_admin
    from firebase_admin import firestore

    if not firebase_admin._apps:
        firebase_admin.initialize_app()
    return firestore.client()


def _unauthenticated() -> https_fn.HttpsError:
    return https_fn.HttpsError(
        code=https_fn.FunctionsErrorCode.UNAUTHENTICATED,
        message="Connexion requise.",
    )


def _denied(message: str = "Accès refusé.") -> https_fn.HttpsError:
    return https_fn.HttpsError(
        code=https_fn.FunctionsErrorCode.PERMISSION_DENIED,
        message=message,
    )


def _token(req: https_fn.CallableRequest) -> dict:
    auth = getattr(req, "auth", None)
    if auth is None or not getattr(auth, "uid", None):
        raise _unauthenticated()
    return getattr(auth, "token", None) or {}


def is_anonymous(req: https_fn.CallableRequest) -> bool:
    """True when the caller signed in with Firebase anonymous auth."""
    firebase_claims = _token(req).get("firebase") or {}
    return firebase_claims.get("sign_in_provider") == "anonymous"


def require_signed_in(req: https_fn.CallableRequest) -> str:
    """Return the caller's uid, or raise UNAUTHENTICATED."""
    _token(req)
    return req.auth.uid


def require_teacher(req: https_fn.CallableRequest) -> str:
    """Return the teacher's uid, or raise.

    Anonymous accounts are never teachers, whatever their Firestore
    profile says.
    """
    uid = require_signed_in(req)
    if is_anonymous(req):
        raise _denied("Réservé aux enseignants.")
    profile = _get_firestore().collection("users").document(uid).get()
    data = profile.to_dict() if profile.exists else None
    if not data or data.get("role") != "teacher":
        raise _denied("Réservé aux enseignants.")
    return uid


def require_student(req: https_fn.CallableRequest) -> StudentIdentity:
    """Return the student identity carried by the caller's custom claims."""
    token = _token(req)
    class_id = token.get("classID")
    student_id = token.get("studentID")
    if (
        token.get("role") != "student"
        or not isinstance(class_id, str)
        or not class_id
        or not isinstance(student_id, str)
        or not student_id
    ):
        raise _denied("Session élève invalide. Reconnectez-vous avec le code classe.")
    return StudentIdentity(uid=req.auth.uid, class_id=class_id, student_id=student_id)


def student_storage_prefix(identity: StudentIdentity) -> str:
    """Cloud Storage folder a student may write to and have read back."""
    return f"submissions/{identity.class_id}/{identity.student_id}/"


def is_safe_path(path: str, prefix: str) -> bool:
    """True when `path` is a plain object path inside `prefix`."""
    return (
        isinstance(path, str)
        and path.startswith(prefix)
        and len(path) > len(prefix)
        and ".." not in path.split("/")
        and "//" not in path
    )
