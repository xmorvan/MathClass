"""
link_student_session.py

Bind an iPad student's anonymous Firebase Auth identity to a Student doc
so the rest of the security model (Firestore rules, Storage rules,
server-side ownership checks in correct_submission / extract_exercise /
recognize_handwriting) can rely on `request.auth.token.studentID`.

Flow:
  1. iPad calls Auth.signInAnonymously() — Firebase mints a UID for the device.
  2. iPad calls linkStudentSession(classID, studentID, deviceToken).
  3. This function verifies the (classID, studentID) pair exists, then:
       - First-time login (no deviceToken stored on the Student doc):
         trust-on-first-use — bind the supplied token to the Student.
       - Subsequent logins from the same device: deviceToken matches → ok.
       - Subsequent logins from a different device: deviceToken mismatch →
         reject. Teacher must explicitly reset the deviceToken before a
         new device can claim that student.
  4. On success, set custom claims {studentID, classID, role:'student'}
     on the caller's anonymous UID via the Admin SDK Auth API.
  5. iPad calls getIDToken(forcingRefresh:true) — the next Firestore /
     Storage / callable request carries the claim.
"""

from firebase_functions import https_fn


def link_student_session_handler(req: https_fn.CallableRequest) -> dict:
    if req.auth is None or not req.auth.uid:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.UNAUTHENTICATED,
            message="Sign in anonymously before linking a student session.",
        )

    if not req.data:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="Aucune donnée fournie.",
        )

    class_id = req.data.get("classID")
    student_id = req.data.get("studentID")
    device_token = req.data.get("deviceToken")

    for name, value in (("classID", class_id), ("studentID", student_id), ("deviceToken", device_token)):
        if not isinstance(value, str) or not value.strip():
            raise https_fn.HttpsError(
                code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
                message=f"'{name}' est requis.",
            )

    # Bound the deviceToken length so a malicious caller can't push a
    # multi-megabyte string into the Student doc (which would balloon every
    # subsequent read of the class roster).
    if len(device_token) > 200:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="'deviceToken' trop long.",
        )

    # Lazy imports — keep deploy introspection time off the critical path.
    import firebase_admin
    from firebase_admin import auth, firestore

    if not firebase_admin._apps:
        firebase_admin.initialize_app()

    db = firestore.client()
    student_ref = (
        db.collection("classes")
        .document(class_id)
        .collection("students")
        .document(student_id)
    )
    snap = student_ref.get()
    if not snap.exists:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.NOT_FOUND,
            message="Élève introuvable dans cette classe.",
        )

    data = snap.to_dict() or {}
    existing_token = data.get("deviceToken")

    if existing_token:
        if existing_token != device_token:
            # Another device already owns this student. The teacher must
            # explicitly clear the deviceToken (e.g. broken iPad replacement)
            # before a different device can claim this identity.
            raise https_fn.HttpsError(
                code=https_fn.FunctionsErrorCode.PERMISSION_DENIED,
                message=(
                    "Cet élève est déjà associé à un autre appareil. "
                    "Demandez à l'enseignant de réinitialiser l'appareil."
                ),
            )
    else:
        # Trust-on-first-use: bind the device token. Any future login from a
        # different device will fail the equality check above.
        student_ref.update({"deviceToken": device_token})

    auth.set_custom_user_claims(
        req.auth.uid,
        {
            "studentID": student_id,
            "classID": class_id,
            "role": "student",
        },
    )

    return {"ok": True, "studentID": student_id, "classID": class_id}
