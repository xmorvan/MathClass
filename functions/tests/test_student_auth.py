"""
Tests for student_auth.py (class-code login and class-code generation).

Firestore is replaced by the in-memory FakeFirestore from conftest and
`firebase_admin.auth.set_custom_user_claims` is captured, so these run
without credentials.

Run with:
    cd functions && python -m pytest tests
"""

from __future__ import annotations

import sys
import types

import pytest

from conftest import FakeFirestore, anonymous_auth, make_request, student_auth, teacher_auth

import auth_guard
import student_auth as sa


https_fn = sys.modules["firebase_functions"].https_fn


def _db():
    return FakeFirestore({
        "users/teacher-1": {"role": "teacher"},
        "classes/class-1": {"name": "3ème A", "classCode": "MX-AB23", "teacherID": "teacher-1"},
        "classes/class-1/students/stu-1": {"firstName": "Camille", "lastName": "Berger"},
        "classes/class-1/students/stu-2": {"firstName": "Alice", "lastName": "Démo", "deviceToken": "ipad-1"},
        "classes/class-2": {"name": "Autre", "classCode": "MX-ZZ99", "teacherID": "teacher-2"},
        "classes/class-2/students/stu-9": {"firstName": "Zoé", "lastName": "Martin"},
    })


@pytest.fixture
def db(monkeypatch):
    fake = _db()
    monkeypatch.setattr(auth_guard, "_get_firestore", lambda: fake)
    return fake


@pytest.fixture
def claims(monkeypatch):
    """Capture custom-claim writes instead of calling Firebase Auth."""
    calls = []
    fake_auth = types.ModuleType("firebase_admin.auth")
    fake_auth.set_custom_user_claims = lambda uid, value: calls.append((uid, value))
    monkeypatch.setitem(sys.modules, "firebase_admin.auth", fake_auth)
    monkeypatch.setattr(sys.modules["firebase_admin"], "auth", fake_auth, raising=False)
    return calls


def _code(excinfo):
    return excinfo.value.code


# ---------------------------------------------------------------------------
# join_class
# ---------------------------------------------------------------------------


def test_join_class_returns_picker_list_with_initials_only(db):
    result = sa.join_class_handler(
        make_request({"classCode": " mx-ab23 "}, auth=anonymous_auth())
    )

    assert result["classID"] == "class-1"
    assert result["className"] == "3ème A"
    assert result["students"] == [
        {"id": "stu-2", "firstName": "Alice", "lastInitial": "D.", "linked": True},
        {"id": "stu-1", "firstName": "Camille", "lastInitial": "B.", "linked": False},
    ]


def test_join_class_requires_sign_in(db):
    with pytest.raises(https_fn.HttpsError) as excinfo:
        sa.join_class_handler(make_request({"classCode": "MX-AB23"}))
    assert _code(excinfo) == https_fn.FunctionsErrorCode.UNAUTHENTICATED


@pytest.mark.parametrize("code", ["MX-0000", "nonsense", ""])
def test_join_class_unknown_code(db, code):
    with pytest.raises(https_fn.HttpsError) as excinfo:
        sa.join_class_handler(
            make_request({"classCode": code}, auth=anonymous_auth())
        )
    assert _code(excinfo) == https_fn.FunctionsErrorCode.NOT_FOUND


# ---------------------------------------------------------------------------
# claim_student_seat
# ---------------------------------------------------------------------------


def test_claim_sets_student_claims(db, claims):
    result = sa.claim_student_seat_handler(
        make_request({"classCode": "MX-AB23", "studentID": "stu-1"}, auth=anonymous_auth("anon-7"))
    )

    assert result == {"classID": "class-1", "studentID": "stu-1"}
    assert claims == [
        ("anon-7", {"role": "student", "classID": "class-1", "studentID": "stu-1"})
    ]


def test_claim_rejects_student_from_another_class(db, claims):
    with pytest.raises(https_fn.HttpsError) as excinfo:
        sa.claim_student_seat_handler(
            make_request({"classCode": "MX-AB23", "studentID": "stu-9"}, auth=anonymous_auth())
        )
    assert _code(excinfo) == https_fn.FunctionsErrorCode.INVALID_ARGUMENT
    assert claims == []


def test_claim_rejects_teacher_accounts(db, claims):
    with pytest.raises(https_fn.HttpsError) as excinfo:
        sa.claim_student_seat_handler(
            make_request({"classCode": "MX-AB23", "studentID": "stu-1"}, auth=teacher_auth())
        )
    assert _code(excinfo) == https_fn.FunctionsErrorCode.PERMISSION_DENIED
    assert claims == []


@pytest.mark.parametrize("student_id", [None, "", "stu-1/levelProgress/x"])
def test_claim_rejects_bad_student_id(db, claims, student_id):
    with pytest.raises(https_fn.HttpsError):
        sa.claim_student_seat_handler(
            make_request({"classCode": "MX-AB23", "studentID": student_id}, auth=anonymous_auth())
        )
    assert claims == []


def test_claim_can_switch_student_on_shared_ipad(db, claims):
    """A shared iPad re-claims: the new claims simply replace the old ones."""
    sa.claim_student_seat_handler(
        make_request(
            {"classCode": "MX-AB23", "studentID": "stu-2"},
            auth=student_auth(class_id="class-1", student_id="stu-1", uid="anon-1"),
        )
    )
    assert claims[-1] == (
        "anon-1", {"role": "student", "classID": "class-1", "studentID": "stu-2"}
    )


# ---------------------------------------------------------------------------
# generate_class_code
# ---------------------------------------------------------------------------


def test_generate_class_code_avoids_existing_codes(db, monkeypatch):
    picks = iter("AB23" + "CD45")  # first candidate collides with class-1
    monkeypatch.setattr(sa.secrets, "choice", lambda _chars: next(picks))

    result = sa.generate_class_code_handler(
        make_request({}, auth=teacher_auth())
    )
    assert result == {"classCode": "MX-CD45"}


def test_generate_class_code_is_teacher_only(db):
    with pytest.raises(https_fn.HttpsError) as excinfo:
        sa.generate_class_code_handler(
            make_request({}, auth=student_auth())
        )
    assert _code(excinfo) == https_fn.FunctionsErrorCode.PERMISSION_DENIED
