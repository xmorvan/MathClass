"""
Smoke tests for recognize_handwriting.py.

Anthropic + Firebase Storage are mocked. Tests cover input validation,
JSON parsing of Claude's response, and the low-confidence error path.

Run with:
    cd functions && python -m pytest tests
"""

from __future__ import annotations

import sys
import types
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


# Same stub setup as the other smoke tests.
if "firebase_functions" not in sys.modules:
    fake_fn = types.ModuleType("firebase_functions")

    class _ErrorCode:
        INVALID_ARGUMENT = "INVALID_ARGUMENT"
        INTERNAL = "INTERNAL"
        NOT_FOUND = "NOT_FOUND"

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

    if "recognize_handwriting" in sys.modules:
        del sys.modules["recognize_handwriting"]
    return importlib.import_module("recognize_handwriting")


def _fake_request(data):
    from firebase_functions import https_fn

    return https_fn.CallableRequest(data)


def _fake_anthropic_response(text):
    msg = MagicMock()
    msg.content = [MagicMock(text=text)]
    return msg


def test_missing_input_raises():
    mod = _import_module()
    from firebase_functions import https_fn

    with pytest.raises(https_fn.HttpsError):
        mod.recognize_handwriting_handler(_fake_request({}))


def test_happy_path_returns_steps(monkeypatch):
    mod = _import_module()
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test-key")

    fake_blob = MagicMock()
    fake_blob.exists.return_value = True
    fake_blob.download_as_bytes.return_value = b"png-bytes"
    fake_bucket = MagicMock()
    fake_bucket.blob.return_value = fake_blob

    response_text = '{"steps": ["x + 1", "x = 2"], "confidence": 0.95}'
    fake_response = _fake_anthropic_response(response_text)
    fake_client = MagicMock()
    fake_client.messages.create.return_value = fake_response

    with patch.object(mod, "storage") as mock_storage, \
         patch("anthropic.Anthropic", return_value=fake_client):
        mock_storage.bucket.return_value = fake_bucket

        result = mod.recognize_handwriting_handler(_fake_request({
            "storagePath": "submissions/abc/ex_attempt1.png",
            "format": "png",
        }))

    assert result["steps"] == ["x + 1", "x = 2"]
    assert result["confidence"] == pytest.approx(0.95)


def test_blank_canvas_returns_empty_steps(monkeypatch):
    """When confidence is below threshold, the function still returns a
    valid response (not an error) so the client can prompt the student
    to redraw."""
    mod = _import_module()
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test-key")

    fake_blob = MagicMock()
    fake_blob.exists.return_value = True
    fake_blob.download_as_bytes.return_value = b""
    fake_bucket = MagicMock()
    fake_bucket.blob.return_value = fake_blob

    response_text = '{"steps": [], "confidence": 0.0}'
    fake_response = _fake_anthropic_response(response_text)
    fake_client = MagicMock()
    fake_client.messages.create.return_value = fake_response

    with patch.object(mod, "storage") as mock_storage, \
         patch("anthropic.Anthropic", return_value=fake_client):
        mock_storage.bucket.return_value = fake_bucket
        result = mod.recognize_handwriting_handler(_fake_request({
            "storagePath": "submissions/abc/ex_attempt1.png",
            "format": "png",
        }))

    assert result["steps"] == []
    assert result["confidence"] == 0.0
