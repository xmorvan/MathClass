"""
delete_student_data.py

Teacher-callable function that hard-deletes a student's personal data:
the student doc itself, every `/submissions/{id}` of that student in that
class, the matching Cloud Storage prefix (submissions/<classID>/<studentID>/,
the layout storage.rules enforces), and any `levelProgress/*` rows under
the student's class subtree.

Student IDs are only unique within a class (demo classes reuse the same
IDs), so every lookup is scoped to the class.

Used to satisfy GDPR / CCPA right-to-erasure requests for minors. Only
the teacher who owns the parent class can invoke this — the function
verifies ownership via the user's email/password Firebase Auth UID
against `classes/{classID}.teacherID`.

Returns the count of submissions deleted so the caller can confirm the
expected magnitude before the dialog closes.
"""

from firebase_functions import https_fn


def delete_student_data_handler(req: https_fn.CallableRequest) -> dict:
    auth = getattr(req, "auth", None)
    if auth is None or not getattr(auth, "uid", None):
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.UNAUTHENTICATED,
            message="Connexion enseignant requise.",
        )

    if not req.data:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="Aucune donnée fournie.",
        )

    class_id = req.data.get("classID")
    student_id = req.data.get("studentID")
    if not isinstance(class_id, str) or not class_id \
            or not isinstance(student_id, str) or not student_id:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="'classID' et 'studentID' sont requis.",
        )

    # Lazy imports — keep deploy introspection time off the critical path.
    import firebase_admin
    from firebase_admin import auth as admin_auth, firestore, storage

    if not firebase_admin._apps:
        firebase_admin.initialize_app()

    db = firestore.client()

    # Ownership check: only the class's teacher can erase.
    class_snap = db.collection("classes").document(class_id).get()
    if not class_snap.exists:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.NOT_FOUND,
            message="Classe introuvable.",
        )
    teacher_id = (class_snap.to_dict() or {}).get("teacherID")
    if teacher_id != auth.uid:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.PERMISSION_DENIED,
            message="Vous n'êtes pas l'enseignant de cette classe.",
        )

    student_ref = (
        db.collection("classes")
        .document(class_id)
        .collection("students")
        .document(student_id)
    )
    student_snap = student_ref.get()
    if not student_snap.exists:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.NOT_FOUND,
            message="Élève introuvable dans cette classe.",
        )

    deleted_submissions = 0
    submissions_query = (
        db.collection("submissions")
        .where("classID", "==", class_id)
        .where("studentID", "==", student_id)
        .stream()
    )
    for sub in submissions_query:
        sub.reference.delete()
        deleted_submissions += 1

    # Per-assignment levelProgress rows under the student subtree.
    deleted_progress = 0
    progress_query = student_ref.collection("levelProgress").stream()
    for row in progress_query:
        row.reference.delete()
        deleted_progress += 1

    # Storage prefix.
    deleted_blobs = 0
    bucket = storage.bucket()
    for blob in bucket.list_blobs(prefix=f"submissions/{class_id}/{student_id}/"):
        blob.delete()
        deleted_blobs += 1

    # Revoke any anonymous Firebase Auth UID that had this student's claim.
    # Best-effort — we don't know the UID directly, only the linked claim,
    # but `revoke_refresh_tokens` on the original UID would happen via the
    # caller-side `Auth.signOut()` after deletion, so we skip it here.

    student_ref.delete()

    return {
        "ok": True,
        "deletedSubmissions": deleted_submissions,
        "deletedLevelProgress": deleted_progress,
        "deletedStorageObjects": deleted_blobs,
    }
