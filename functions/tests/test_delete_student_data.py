"""Smoke tests for delete_student_data.py (ISSUE-014 §3.6).

Cover:
- Happy path: cascade delete (student + submissions + levelProgress + Storage).
- Non-owner teacher rejected.
- Unauthenticated caller rejected.
- Missing class / student returns NOT_FOUND.
"""

from __future__ import annotations

import sys
import types
from unittest.mock import MagicMock

import pytest

import delete_student_data as dsd


def _fake_request(data, uid: str | None = "teacher-uid") -> object:
    auth = None if uid is None else types.SimpleNamespace(uid=uid, token={})
    return types.SimpleNamespace(data=data, auth=auth)


def _build_db(
    *,
    class_data: dict | None,
    student_exists: bool,
    submission_ids: list[str],
    progress_ids: list[str],
) -> tuple[MagicMock, list[MagicMock], list[MagicMock], MagicMock]:
    """Wire a chain of MagicMocks that mimics the call graph used by the
    handler. Returns (db, submission_refs, progress_refs, student_ref) so
    tests can assert that delete() fired the right number of times.
    """
    class_snap = MagicMock()
    class_snap.exists = class_data is not None
    if class_data is not None:
        class_snap.to_dict.return_value = class_data

    student_snap = MagicMock()
    student_snap.exists = student_exists

    submission_refs: list[MagicMock] = []
    submission_docs: list[MagicMock] = []
    for sid in submission_ids:
        ref = MagicMock(name=f"submission_ref_{sid}")
        doc = MagicMock(name=f"submission_doc_{sid}")
        doc.reference = ref
        submission_refs.append(ref)
        submission_docs.append(doc)

    progress_refs: list[MagicMock] = []
    progress_docs: list[MagicMock] = []
    for pid in progress_ids:
        ref = MagicMock(name=f"progress_ref_{pid}")
        doc = MagicMock(name=f"progress_doc_{pid}")
        doc.reference = ref
        progress_refs.append(ref)
        progress_docs.append(doc)

    student_ref = MagicMock(name="student_ref")
    student_ref.get.return_value = student_snap
    student_ref.collection.return_value.stream.return_value = iter(progress_docs)

    class_ref = MagicMock(name="class_ref")
    class_ref.get.return_value = class_snap
    class_ref.collection.return_value.document.return_value = student_ref

    submissions_query = MagicMock(name="submissions_query")
    submissions_query.stream.return_value = iter(submission_docs)
    submissions_collection = MagicMock(name="submissions_collection")
    submissions_collection.where.return_value = submissions_query
    # The handler chains .where(classID).where(studentID).
    submissions_query.where.return_value = submissions_query

    db = MagicMock(name="db")

    def collection_router(name):
        if name == "classes":
            outer = MagicMock()
            outer.document.return_value = class_ref
            return outer
        if name == "submissions":
            return submissions_collection
        return MagicMock()

    db.collection.side_effect = collection_router
    return db, submission_refs, progress_refs, student_ref


def _build_bucket(prefix_blob_count: int) -> tuple[MagicMock, list[MagicMock]]:
    blobs = [MagicMock(name=f"blob_{i}") for i in range(prefix_blob_count)]
    bucket = MagicMock(name="bucket")
    # Blobs sit under the current submissions/{classID}/{studentID}/ layout;
    # the legacy submissions/{studentID}/ prefix is empty.
    bucket.list_blobs.side_effect = lambda prefix: blobs if prefix.count("/") == 3 else []
    return bucket, blobs


# ---------------------------------------------------------------------------
# Happy path
# ---------------------------------------------------------------------------


def test_full_cascade(monkeypatch):
    """Teacher owns the class → student doc + 3 submissions + 2 progress
    rows + 4 storage blobs all deleted."""
    db, sub_refs, prog_refs, student_ref = _build_db(
        class_data={"teacherID": "teacher-uid"},
        student_exists=True,
        submission_ids=["s1", "s2", "s3"],
        progress_ids=["p1", "p2"],
    )
    bucket, blobs = _build_bucket(prefix_blob_count=4)

    monkeypatch.setattr(
        sys.modules["firebase_admin.firestore"], "client", lambda: db
    )
    monkeypatch.setattr(
        sys.modules["firebase_admin.storage"], "bucket", lambda: bucket
    )

    result = dsd.delete_student_data_handler(_fake_request({
        "classID": "cls1",
        "studentID": "stu1",
    }))

    assert result == {
        "ok": True,
        "deletedSubmissions": 3,
        "deletedLevelProgress": 2,
        "deletedStorageObjects": 4,
    }
    for ref in sub_refs:
        ref.delete.assert_called_once()
    for ref in prog_refs:
        ref.delete.assert_called_once()
    for blob in blobs:
        blob.delete.assert_called_once()
    student_ref.delete.assert_called_once()


# ---------------------------------------------------------------------------
# Rejection paths
# ---------------------------------------------------------------------------


def test_non_owner_teacher_rejected(monkeypatch):
    """Teacher A trying to delete a student in teacher B's class →
    PERMISSION_DENIED, no deletes."""
    db, sub_refs, _, student_ref = _build_db(
        class_data={"teacherID": "other-teacher"},
        student_exists=True,
        submission_ids=["s1"],
        progress_ids=[],
    )
    monkeypatch.setattr(
        sys.modules["firebase_admin.firestore"], "client", lambda: db
    )

    https_fn = sys.modules["firebase_functions"].https_fn
    with pytest.raises(https_fn.HttpsError) as exc:
        dsd.delete_student_data_handler(_fake_request({
            "classID": "cls1",
            "studentID": "stu1",
        }))
    assert exc.value.code == https_fn.FunctionsErrorCode.PERMISSION_DENIED
    student_ref.delete.assert_not_called()
    for ref in sub_refs:
        ref.delete.assert_not_called()


def test_unauthenticated_caller_rejected():
    https_fn = sys.modules["firebase_functions"].https_fn
    with pytest.raises(https_fn.HttpsError) as exc:
        dsd.delete_student_data_handler(_fake_request({
            "classID": "cls1",
            "studentID": "stu1",
        }, uid=None))
    assert exc.value.code == https_fn.FunctionsErrorCode.UNAUTHENTICATED


@pytest.mark.parametrize("missing", ["classID", "studentID"])
def test_missing_required_field_rejected(missing):
    payload = {"classID": "cls1", "studentID": "stu1"}
    payload[missing] = ""

    https_fn = sys.modules["firebase_functions"].https_fn
    with pytest.raises(https_fn.HttpsError) as exc:
        dsd.delete_student_data_handler(_fake_request(payload))
    assert exc.value.code == https_fn.FunctionsErrorCode.INVALID_ARGUMENT


def test_unknown_class_returns_not_found(monkeypatch):
    db, _, _, _ = _build_db(
        class_data=None,
        student_exists=False,
        submission_ids=[],
        progress_ids=[],
    )
    monkeypatch.setattr(
        sys.modules["firebase_admin.firestore"], "client", lambda: db
    )
    https_fn = sys.modules["firebase_functions"].https_fn
    with pytest.raises(https_fn.HttpsError) as exc:
        dsd.delete_student_data_handler(_fake_request({
            "classID": "missing",
            "studentID": "stu1",
        }))
    assert exc.value.code == https_fn.FunctionsErrorCode.NOT_FOUND


def test_unknown_student_returns_not_found(monkeypatch):
    db, _, _, _ = _build_db(
        class_data={"teacherID": "teacher-uid"},
        student_exists=False,
        submission_ids=[],
        progress_ids=[],
    )
    monkeypatch.setattr(
        sys.modules["firebase_admin.firestore"], "client", lambda: db
    )
    https_fn = sys.modules["firebase_functions"].https_fn
    with pytest.raises(https_fn.HttpsError) as exc:
        dsd.delete_student_data_handler(_fake_request({
            "classID": "cls1",
            "studentID": "ghost",
        }))
    assert exc.value.code == https_fn.FunctionsErrorCode.NOT_FOUND


def test_submissions_are_scoped_to_the_class(monkeypatch):
    """Demo student IDs repeat across teachers: the query must filter on
    classID as well as studentID, and storage uses the class prefix."""
    db, _, _, _ = _build_db(
        class_data={"teacherID": "teacher-uid"},
        student_exists=True,
        submission_ids=["s1"],
        progress_ids=[],
    )
    bucket, _ = _build_bucket(prefix_blob_count=1)
    monkeypatch.setattr(sys.modules["firebase_admin.firestore"], "client", lambda: db)
    monkeypatch.setattr(sys.modules["firebase_admin.storage"], "bucket", lambda: bucket)

    dsd.delete_student_data_handler(_fake_request({"classID": "cls1", "studentID": "stu1"}))

    submissions = db.collection("submissions")
    first_filter = submissions.where.call_args.args
    second_filter = submissions.where.return_value.where.call_args.args
    assert first_filter == ("classID", "==", "cls1")
    assert second_filter == ("studentID", "==", "stu1")
    prefixes = [c.kwargs.get("prefix") or c.args[0] for c in bucket.list_blobs.call_args_list]
    assert "submissions/cls1/stu1/" in prefixes
