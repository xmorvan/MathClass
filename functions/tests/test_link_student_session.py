"""Smoke tests for link_student_session.py (ISSUE-014).

Cover:
- Happy path: TOFU bind of deviceToken + custom-claim set.
- Returning device: deviceToken matches existing → claims refreshed, no doc write.
- Wrong device: deviceToken mismatch → PERMISSION_DENIED + no claim set.
- Missing auth, missing payload fields, unknown student → INVALID_ARGUMENT/UNAUTHENTICATED/NOT_FOUND.

The Firestore + Admin Auth SDKs are stubbed via `conftest.py` and patched
per-test through monkeypatch.
"""

from __future__ import annotations

import sys
import types
from unittest.mock import MagicMock

import pytest

import link_student_session as lss


# ---------------------------------------------------------------------------
# Test fixtures
# ---------------------------------------------------------------------------


def _fake_request(data, uid: str = "anon-uid") -> object:
    """Stub CallableRequest. Pass `uid=None` to simulate an unauthenticated
    caller; pass a string to provide the anonymous Firebase Auth UID."""
    auth = None if uid is None else types.SimpleNamespace(uid=uid, token={})
    return types.SimpleNamespace(data=data, auth=auth)


def _stub_firestore_with(student_data: dict | None) -> tuple[MagicMock, MagicMock]:
    """Build a fake firestore client whose student doc exists iff
    `student_data` is non-None. Returns (db_mock, student_ref_mock)."""
    student_snap = MagicMock()
    student_snap.exists = student_data is not None
    student_snap.to_dict.return_value = student_data or {}

    student_ref = MagicMock()
    student_ref.get.return_value = student_snap

    db = MagicMock()
    db.collection.return_value.document.return_value.collection.return_value.document.return_value = student_ref
    return db, student_ref


@pytest.fixture(autouse=True)
def _reset_auth_stub(monkeypatch):
    # Replace the auth stub's set_custom_user_claims with a fresh mock per
    # test so assertions on call args don't leak across tests.
    fresh = MagicMock()
    monkeypatch.setattr(sys.modules["firebase_admin.auth"], "set_custom_user_claims", fresh)
    return fresh


# ---------------------------------------------------------------------------
# Happy paths
# ---------------------------------------------------------------------------


def test_first_login_binds_device_token(monkeypatch, _reset_auth_stub):
    """TOFU: empty deviceToken on Student → function writes the supplied token."""
    db, student_ref = _stub_firestore_with({"firstName": "Alice", "deviceToken": None})
    monkeypatch.setattr(
        sys.modules["firebase_admin.firestore"], "client", lambda: db
    )

    result = lss.link_student_session_handler(_fake_request({
        "classID": "cls1",
        "studentID": "stu1",
        "deviceToken": "ipad-token-A",
    }))

    assert result["ok"] is True
    assert result["studentID"] == "stu1"
    student_ref.update.assert_called_once_with({"deviceToken": "ipad-token-A"})
    _reset_auth_stub.assert_called_once_with(
        "anon-uid",
        {"studentID": "stu1", "classID": "cls1", "role": "student"},
    )


def test_returning_device_reuses_token(monkeypatch, _reset_auth_stub):
    """Same device coming back: existing token matches → no doc write, but
    claims are refreshed in case they were revoked."""
    db, student_ref = _stub_firestore_with({"deviceToken": "ipad-token-A"})
    monkeypatch.setattr(
        sys.modules["firebase_admin.firestore"], "client", lambda: db
    )

    result = lss.link_student_session_handler(_fake_request({
        "classID": "cls1",
        "studentID": "stu1",
        "deviceToken": "ipad-token-A",
    }))

    assert result["ok"] is True
    student_ref.update.assert_not_called()
    _reset_auth_stub.assert_called_once()


# ---------------------------------------------------------------------------
# Rejection paths
# ---------------------------------------------------------------------------


def test_mismatched_device_is_rejected(monkeypatch, _reset_auth_stub):
    """Different device: existing token doesn't match → PERMISSION_DENIED
    and no custom claim set."""
    db, student_ref = _stub_firestore_with({"deviceToken": "ipad-A"})
    monkeypatch.setattr(
        sys.modules["firebase_admin.firestore"], "client", lambda: db
    )

    https_fn = sys.modules["firebase_functions"].https_fn
    with pytest.raises(https_fn.HttpsError) as exc:
        lss.link_student_session_handler(_fake_request({
            "classID": "cls1",
            "studentID": "stu1",
            "deviceToken": "ipad-B-impostor",
        }))
    assert exc.value.code == https_fn.FunctionsErrorCode.PERMISSION_DENIED
    student_ref.update.assert_not_called()
    _reset_auth_stub.assert_not_called()


def test_unauthenticated_caller_rejected():
    https_fn = sys.modules["firebase_functions"].https_fn
    with pytest.raises(https_fn.HttpsError) as exc:
        lss.link_student_session_handler(_fake_request({
            "classID": "cls1",
            "studentID": "stu1",
            "deviceToken": "x",
        }, uid=None))
    assert exc.value.code == https_fn.FunctionsErrorCode.UNAUTHENTICATED


@pytest.mark.parametrize("missing_field", ["classID", "studentID", "deviceToken"])
def test_missing_required_field_rejected(missing_field):
    payload = {"classID": "cls1", "studentID": "stu1", "deviceToken": "x"}
    payload[missing_field] = ""

    https_fn = sys.modules["firebase_functions"].https_fn
    with pytest.raises(https_fn.HttpsError) as exc:
        lss.link_student_session_handler(_fake_request(payload))
    assert exc.value.code == https_fn.FunctionsErrorCode.INVALID_ARGUMENT


def test_unknown_student_returns_not_found(monkeypatch):
    db, _ = _stub_firestore_with(None)  # student doc missing
    monkeypatch.setattr(
        sys.modules["firebase_admin.firestore"], "client", lambda: db
    )

    https_fn = sys.modules["firebase_functions"].https_fn
    with pytest.raises(https_fn.HttpsError) as exc:
        lss.link_student_session_handler(_fake_request({
            "classID": "cls1",
            "studentID": "stuX",
            "deviceToken": "x",
        }))
    assert exc.value.code == https_fn.FunctionsErrorCode.NOT_FOUND


def test_oversize_device_token_rejected():
    https_fn = sys.modules["firebase_functions"].https_fn
    with pytest.raises(https_fn.HttpsError) as exc:
        lss.link_student_session_handler(_fake_request({
            "classID": "cls1",
            "studentID": "stu1",
            "deviceToken": "x" * 201,  # cap is 200
        }))
    assert exc.value.code == https_fn.FunctionsErrorCode.INVALID_ARGUMENT
