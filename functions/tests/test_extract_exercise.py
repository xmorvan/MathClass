"""
Smoke tests for extract_exercise.py.

The Anthropic vision call and Firebase Storage download are mocked. The
tests cover the input-validation surface and the post-processing logic
that filters AI-suggested competency IDs against the supplied catalog.

Run with:
    cd functions && python -m pytest tests
"""

from __future__ import annotations

import sys
import types
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from conftest import FakeFirestore, make_request, student_auth, teacher_auth


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


# Reuse the same firebase_functions stub layout as the existing
# correct_submission tests so importing extract_exercise works under
# pytest without the real `firebase-functions` package installed.
if "firebase_functions" not in sys.modules:
    fake_fn = types.ModuleType("firebase_functions")

    class _ErrorCode:
        INVALID_ARGUMENT = "INVALID_ARGUMENT"
        INTERNAL = "INTERNAL"
        NOT_FOUND = "NOT_FOUND"
        UNAUTHENTICATED = "UNAUTHENTICATED"
        PERMISSION_DENIED = "PERMISSION_DENIED"

    class _HttpsError(Exception):
        def __init__(self, code, message, details=None):
            super().__init__(message)
            self.code = code
            self.message = message
            self.details = details

    class _CallableRequest:
        def __init__(self, data):
            self.data = data

    fake_https = types.ModuleType("firebase_functions.https_fn")
    fake_https.FunctionsErrorCode = _ErrorCode
    fake_https.HttpsError = _HttpsError
    fake_https.CallableRequest = _CallableRequest
    fake_fn.https_fn = fake_https
    sys.modules["firebase_functions"] = fake_fn
    sys.modules["firebase_functions.https_fn"] = fake_https

# Stub firebase_admin to avoid touching credentials.
if "firebase_admin" not in sys.modules:
    fake_admin = types.ModuleType("firebase_admin")
    fake_admin._apps = ["fake"]
    fake_admin.initialize_app = lambda *a, **kw: None
    fake_storage_module = types.ModuleType("firebase_admin.storage")
    fake_admin.storage = fake_storage_module
    sys.modules["firebase_admin"] = fake_admin
    sys.modules["firebase_admin.storage"] = fake_storage_module


def _import_module():
    import importlib

    # Force reimport so the stubs above take effect.
    if "extract_exercise" in sys.modules:
        del sys.modules["extract_exercise"]
    return importlib.import_module("extract_exercise")


def _fake_request(data, auth=None):
    return make_request(data, auth=auth if auth is not None else teacher_auth())


@pytest.fixture(autouse=True)
def _teacher_profile(monkeypatch):
    """`teacher-1` is a teacher; everyone else has no profile."""
    import auth_guard

    db = FakeFirestore({"users/teacher-1": {"role": "teacher"}})
    monkeypatch.setattr(auth_guard, "_get_firestore", lambda: db)


def _fake_anthropic_response(text):
    msg = MagicMock()
    msg.content = [MagicMock(text=text)]
    return msg


def test_missing_storage_path_raises():
    mod = _import_module()
    from firebase_functions import https_fn

    with pytest.raises(https_fn.HttpsError):
        mod.extract_exercise_handler(_fake_request({}))


def test_competency_filtering_drops_hallucinations(monkeypatch):
    """Claude may return IDs that don't exist in the catalog. The handler
    must filter them out so the client never sees stale references."""
    mod = _import_module()
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test-key")

    fake_blob = MagicMock()
    fake_blob.exists.return_value = True
    fake_blob.download_as_bytes.return_value = b"fake-png-bytes"
    fake_bucket = MagicMock()
    fake_bucket.blob.return_value = fake_blob

    fake_response = _fake_anthropic_response(
        '{"statement": "S", "expectedAnswer": "x=1", '
        '"competencyIDs": ["valid-1", "halluc-2", "valid-3"]}'
    )
    fake_client = MagicMock()
    fake_client.messages.create.return_value = fake_response

    with patch.object(mod, "storage") as mock_storage, \
         patch("anthropic.Anthropic", return_value=fake_client):
        mock_storage.bucket.return_value = fake_bucket

        result = mod.extract_exercise_handler(_fake_request({
            "storagePath": "exercises/abc.jpg",
            "competencies": [
                {"id": "valid-1", "label": "Linear equations"},
                {"id": "valid-3", "label": "Quadratics"},
            ],
        }))

    assert result["statement"] == "S"
    assert result["expectedAnswer"] == "x=1"
    # Hallucinated ID dropped; valid ones preserved.
    assert sorted(result["competencyIDs"]) == ["valid-1", "valid-3"]


def test_empty_extraction_rejected(monkeypatch):
    mod = _import_module()
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test-key")

    fake_blob = MagicMock()
    fake_blob.exists.return_value = True
    fake_blob.download_as_bytes.return_value = b"fake"
    fake_bucket = MagicMock()
    fake_bucket.blob.return_value = fake_blob

    fake_response = _fake_anthropic_response(
        '{"statement": "", "expectedAnswer": "", "competencyIDs": []}'
    )
    fake_client = MagicMock()
    fake_client.messages.create.return_value = fake_response

    from firebase_functions import https_fn
    with patch.object(mod, "storage") as mock_storage, \
         patch("anthropic.Anthropic", return_value=fake_client):
        mock_storage.bucket.return_value = fake_bucket
        with pytest.raises(https_fn.HttpsError):
            mod.extract_exercise_handler(_fake_request({
                "storagePath": "exercises/abc.jpg",
            }))


# ---------------------------------------------------------------------------
# Authorization
# ---------------------------------------------------------------------------


def _error_code(excinfo):
    return excinfo.value.code


def test_rejects_unauthenticated_caller():
    mod = _import_module()
    from firebase_functions import https_fn

    req = make_request({"storagePath": "exercises/abc.jpg"}, auth=None)
    with pytest.raises(https_fn.HttpsError) as excinfo:
        mod.extract_exercise_handler(req)
    assert _error_code(excinfo) == https_fn.FunctionsErrorCode.UNAUTHENTICATED


def test_rejects_students():
    mod = _import_module()
    from firebase_functions import https_fn

    req = _fake_request({"storagePath": "exercises/abc.jpg"}, auth=student_auth())
    with pytest.raises(https_fn.HttpsError) as excinfo:
        mod.extract_exercise_handler(req)
    assert _error_code(excinfo) == https_fn.FunctionsErrorCode.PERMISSION_DENIED


def test_rejects_signed_in_user_without_teacher_profile():
    mod = _import_module()
    from firebase_functions import https_fn

    req = _fake_request({"storagePath": "exercises/abc.jpg"}, auth=teacher_auth("someone-else"))
    with pytest.raises(https_fn.HttpsError) as excinfo:
        mod.extract_exercise_handler(req)
    assert _error_code(excinfo) == https_fn.FunctionsErrorCode.PERMISSION_DENIED


@pytest.mark.parametrize("path", [
    "submissions/class-1/stu-1/ex_attempt1.png",
    "exercises/../submissions/class-1/stu-1/x.png",
    "exercises/",
])
def test_rejects_paths_outside_exercises(path):
    mod = _import_module()
    from firebase_functions import https_fn

    with pytest.raises(https_fn.HttpsError) as excinfo:
        mod.extract_exercise_handler(_fake_request({"storagePath": path}))
    assert _error_code(excinfo) == https_fn.FunctionsErrorCode.PERMISSION_DENIED


def test_normalize_expected_answer_keeps_final_line_only():
    mod = _import_module()
    assert mod.normalize_expected_answer("$4x + 2 = 18\n4x = 16\nx = 4$") == "x = 4"
    assert mod.normalize_expected_answer("x = 4") == "x = 4"
    assert mod.normalize_expected_answer("x = 1 \\text{ ou } x = 2") == "x = 1 \\text{ ou } x = 2"
    assert mod.normalize_expected_answer(None) == ""
