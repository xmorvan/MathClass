"""
Tests for data_deletion.py (class and account deletion, retention purge).

Firestore and Cloud Storage are in-memory fakes from conftest; Firebase
Auth user deletion is captured.

Run with:
    cd functions && python -m pytest tests
"""

from __future__ import annotations

import datetime
import sys
import types

import pytest

from conftest import FakeBucket, FakeFirestore, make_request, student_auth, teacher_auth

import auth_guard
import data_deletion


https_fn = sys.modules["firebase_functions"].https_fn
NOW = datetime.datetime(2026, 9, 25, tzinfo=datetime.timezone.utc)
RECENT = NOW - datetime.timedelta(days=10)
OLD = NOW - datetime.timedelta(days=400)


def _docs():
    return {
        "users/teacher-1": {"role": "teacher"},
        "users/teacher-2": {"role": "teacher"},
        "classes/class-1": {"teacherID": "teacher-1", "classCode": "MX-AB23"},
        "classes/class-1/students/stu-1": {"firstName": "Camille"},
        "classes/class-1/students/stu-1/levelProgress/asg-1": {"currentLevel": 2},
        "classes/class-1/groups/g-1": {"name": "A"},
        "classes/class-1/chapters/ch-1": {"name": "Équations"},
        "classes/class-1/chapters/ch-1/competencies/c-1": {"label": "1er degré"},
        "classes/class-1b": {"teacherID": "teacher-1", "classCode": "MX-CD45"},
        "classes/class-2": {"teacherID": "teacher-2", "classCode": "MX-ZZ99"},
        "classes/class-2/students/stu-9": {"firstName": "Zoé"},
        "assignments/asg-1": {"classID": "class-1"},
        "assignments/asg-1/exercises/ae-1": {"exerciseID": "ex-1"},
        "assignments/asg-2": {"classID": "class-2"},
        "periods/p-1": {"classID": "class-1"},
        "periods/p-1/sessions/s-1": {"order": 0},
        "periods/p-1/sessions/s-1/exercises/ae-1": {"exerciseID": "ex-1"},
        "periods/p-2": {"classID": "class-2"},
        "exercises/ex-1": {"teacherID": "teacher-1", "statementImageURL": "exercises/ex-1.jpg"},
        "exercises/ex-2": {"teacherID": "teacher-2"},
        "submissions/sub-1": {
            "classID": "class-1", "teacherID": "teacher-1", "studentID": "stu-1",
            "pngURL": "submissions/class-1/stu-1/ex-1_attempt1.png", "timestamp": RECENT,
        },
        "submissions/sub-old": {
            "classID": "class-2", "teacherID": "teacher-2", "studentID": "stu-9",
            "pngURL": "submissions/class-2/stu-9/ex-2_attempt1.png", "timestamp": OLD,
        },
        "submissions/sub-9": {
            "classID": "class-2", "teacherID": "teacher-2", "studentID": "stu-9",
            "pngURL": "submissions/class-2/stu-9/ex-2_attempt2.png", "timestamp": RECENT,
        },
    }


@pytest.fixture
def env(monkeypatch):
    db = FakeFirestore(_docs())
    bucket = FakeBucket({
        "submissions/class-1/stu-1/ex-1_attempt1.png",
        "submissions/class-1/stu-1/orphan.png",
        "submissions/class-2/stu-9/ex-2_attempt1.png",
        "submissions/class-2/stu-9/ex-2_attempt2.png",
        "exercises/ex-1.jpg",
    })
    deleted_users = []
    fake_auth = types.ModuleType("firebase_admin.auth")
    fake_auth.delete_user = deleted_users.append
    monkeypatch.setitem(sys.modules, "firebase_admin.auth", fake_auth)
    monkeypatch.setattr(sys.modules["firebase_admin"], "auth", fake_auth, raising=False)
    monkeypatch.setattr(auth_guard, "_get_firestore", lambda: db)
    monkeypatch.setattr(data_deletion, "_bucket", lambda: bucket)
    return types.SimpleNamespace(db=db, bucket=bucket, deleted_users=deleted_users)


def _remaining(env, prefix):
    return sorted(p for p in env.db.docs if p.startswith(prefix))


# ---------------------------------------------------------------------------
# delete_class
# ---------------------------------------------------------------------------


def test_delete_class_removes_everything_of_that_class_only(env):
    result = data_deletion.delete_class_handler(
        make_request({"classID": "class-1"}, auth=teacher_auth())
    )

    assert result == {"deleted": "class-1"}
    assert _remaining(env, "classes/class-1/") == []
    assert "classes/class-1" not in env.db.docs
    assert _remaining(env, "assignments/asg-1") == []
    assert _remaining(env, "periods/p-1") == []
    assert "submissions/sub-1" not in env.db.docs
    assert not any(p.startswith("submissions/class-1/") for p in env.bucket.paths)
    # Other classes, the teacher's other class and the exercise library stay.
    assert "classes/class-1b" in env.db.docs
    assert "classes/class-2/students/stu-9" in env.db.docs
    assert {"assignments/asg-2", "periods/p-2", "submissions/sub-9", "exercises/ex-1"} <= set(env.db.docs)
    assert "exercises/ex-1.jpg" in env.bucket.paths


@pytest.mark.parametrize("auth, class_id, expected", [
    (teacher_auth("teacher-2"), "class-1", "PERMISSION_DENIED"),
    (student_auth(), "class-1", "PERMISSION_DENIED"),
    (None, "class-1", "UNAUTHENTICATED"),
    (teacher_auth(), "missing", "NOT_FOUND"),
    (teacher_auth(), "", "INVALID_ARGUMENT"),
    (teacher_auth(), "class-1/students", "INVALID_ARGUMENT"),
])
def test_delete_class_rejections(env, auth, class_id, expected):
    before = dict(env.db.docs)
    with pytest.raises(https_fn.HttpsError) as excinfo:
        data_deletion.delete_class_handler(make_request({"classID": class_id}, auth=auth))
    assert excinfo.value.code == getattr(https_fn.FunctionsErrorCode, expected)
    assert env.db.docs == before


# ---------------------------------------------------------------------------
# delete_account
# ---------------------------------------------------------------------------


def test_delete_account_removes_all_teacher_data_and_auth_user(env):
    result = data_deletion.delete_account_handler(make_request({}, auth=teacher_auth()))

    assert result == {"deletedClasses": 2}
    assert env.deleted_users == ["teacher-1"]
    remaining = set(env.db.docs)
    assert not any(p.startswith(("classes/class-1", "users/teacher-1")) for p in remaining)
    assert {"exercises/ex-1", "submissions/sub-1", "assignments/asg-1", "periods/p-1"}.isdisjoint(remaining)
    assert "exercises/ex-1.jpg" not in env.bucket.paths
    # teacher-2 untouched
    assert {"users/teacher-2", "classes/class-2", "exercises/ex-2", "submissions/sub-9"} <= remaining


def test_delete_account_is_teacher_only(env):
    with pytest.raises(https_fn.HttpsError):
        data_deletion.delete_account_handler(make_request({}, auth=student_auth()))
    assert env.deleted_users == []


# ---------------------------------------------------------------------------
# purge_old_submissions
# ---------------------------------------------------------------------------


def test_purge_deletes_only_submissions_past_retention(env):
    deleted = data_deletion.purge_old_submissions(now=NOW)

    assert deleted == 1
    assert "submissions/sub-old" not in env.db.docs
    assert "submissions/class-2/stu-9/ex-2_attempt1.png" not in env.bucket.paths
    assert {"submissions/sub-1", "submissions/sub-9"} <= set(env.db.docs)
    assert "submissions/class-2/stu-9/ex-2_attempt2.png" in env.bucket.paths
