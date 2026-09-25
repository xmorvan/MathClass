"""
student_auth.py
Class-code login for students, done server-side.

Students have no email account. The iPad signs in with Firebase anonymous
auth, then:
  1. `join_class` turns a class code into the class name and the list of
     students to pick from (first name + last-name initial only).
  2. `claim_student_seat` checks the code and the chosen student again,
     then stamps the anonymous account with the custom claims
     {role: "student", classID, studentID}. Security rules rely on these
     claims, so a student can only read and write their own data.

`generate_class_code` lets a teacher get a code that no other class uses,
without being able to query other teachers' classes.
"""

from __future__ import annotations

import re
import secrets

from firebase_functions import https_fn

import auth_guard

CODE_CHARACTERS = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
CODE_PATTERN = re.compile(r"^MX-[A-Z0-9]{4}$")


def _invalid(message: str) -> https_fn.HttpsError:
    return https_fn.HttpsError(
        code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
        message=message,
    )


def _not_found() -> https_fn.HttpsError:
    return https_fn.HttpsError(
        code=https_fn.FunctionsErrorCode.NOT_FOUND,
        message="Code classe introuvable. Vérifiez le code et réessayez.",
    )


def _normalize_code(raw) -> str:
    if not isinstance(raw, str):
        raise _invalid("'classCode' est requis.")
    code = raw.strip().upper()
    if not CODE_PATTERN.match(code):
        raise _not_found()
    return code


def _find_class(db, code: str):
    """Return the class snapshot for `code`, or None."""
    matches = list(
        db.collection("classes").where("classCode", "==", code).limit(1).stream()
    )
    return matches[0] if matches else None


def _public_student(snapshot) -> dict:
    data = snapshot.to_dict() or {}
    last_name = str(data.get("lastName") or "").strip()
    return {
        "id": snapshot.id,
        "firstName": str(data.get("firstName") or "").strip(),
        # Initial only: enough to tell two "Camille" apart, without handing
        # the full roster to anyone who guesses a code.
        "lastInitial": f"{last_name[0]}." if last_name else "",
        # Drives the "already linked to an iPad" badge in the picker.
        "linked": bool(data.get("deviceToken")),
    }


def join_class_handler(req: https_fn.CallableRequest) -> dict:
    auth_guard.require_signed_in(req)
    code = _normalize_code((req.data or {}).get("classCode"))

    db = auth_guard._get_firestore()
    class_snapshot = _find_class(db, code)
    if class_snapshot is None:
        raise _not_found()

    class_data = class_snapshot.to_dict() or {}
    students = [
        _public_student(s)
        for s in db.collection("classes")
        .document(class_snapshot.id)
        .collection("students")
        .stream()
    ]
    students.sort(key=lambda s: (s["firstName"].lower(), s["lastInitial"].lower()))

    return {
        "classID": class_snapshot.id,
        "className": class_data.get("name", ""),
        "students": students,
    }


def claim_student_seat_handler(req: https_fn.CallableRequest) -> dict:
    uid = auth_guard.require_signed_in(req)
    if not auth_guard.is_anonymous(req):
        # A teacher account must never pick up student claims.
        raise auth_guard._denied("Déconnectez le compte enseignant avant de rejoindre une classe.")

    data = req.data or {}
    code = _normalize_code(data.get("classCode"))
    student_id = data.get("studentID")
    if not isinstance(student_id, str) or not student_id or "/" in student_id:
        raise _invalid("'studentID' est requis.")

    db = auth_guard._get_firestore()
    class_snapshot = _find_class(db, code)
    if class_snapshot is None:
        raise _not_found()

    student = (
        db.collection("classes")
        .document(class_snapshot.id)
        .collection("students")
        .document(student_id)
        .get()
    )
    if not student.exists:
        raise _invalid("Élève introuvable dans cette classe.")

    from firebase_admin import auth

    auth.set_custom_user_claims(
        uid,
        {"role": "student", "classID": class_snapshot.id, "studentID": student_id},
    )
    return {"classID": class_snapshot.id, "studentID": student_id}


def generate_class_code_handler(req: https_fn.CallableRequest) -> dict:
    auth_guard.require_teacher(req)
    db = auth_guard._get_firestore()
    for _ in range(10):
        code = "MX-" + "".join(secrets.choice(CODE_CHARACTERS) for _ in range(4))
        if _find_class(db, code) is None:
            return {"classCode": code}
    raise https_fn.HttpsError(
        code=https_fn.FunctionsErrorCode.INTERNAL,
        message="Impossible de générer un code classe unique.",
    )
