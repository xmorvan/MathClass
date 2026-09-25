"""
Shared pytest setup for the functions/ test suite.

Stubs `firebase_functions` and `firebase_admin` (with both `storage` and
`firestore` submodules) once at collection time so individual test files
don't have to compete with each other to register stubs. Without this,
collection order between `test_correct_submission`, `test_extract_exercise`,
and `test_recognize_handwriting` can leave stubs in an inconsistent state
where the firestore submodule is missing.
"""

from __future__ import annotations

import sys
import types
from pathlib import Path
from unittest.mock import MagicMock

# Make the functions/ directory importable for tests.
ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))


# --- firebase_functions stub --------------------------------------------------

if "firebase_functions" not in sys.modules:
    fake_fn = types.ModuleType("firebase_functions")

    class _ErrorCode:
        INVALID_ARGUMENT = "invalid-argument"
        INTERNAL = "internal"
        UNAVAILABLE = "unavailable"
        NOT_FOUND = "not-found"
        UNAUTHENTICATED = "unauthenticated"
        PERMISSION_DENIED = "permission-denied"

    class _HttpsError(Exception):
        def __init__(self, code, message, details=None):
            self.code = code
            self.message = message
            self.details = details
            super().__init__(message)

    class _CallableRequest:
        def __init__(self, data):
            self.data = data

    fake_https = types.SimpleNamespace(
        FunctionsErrorCode=_ErrorCode,
        HttpsError=_HttpsError,
        on_call=lambda **_: (lambda fn: fn),
        CallableRequest=_CallableRequest,
    )
    fake_fn.https_fn = fake_https
    sys.modules["firebase_functions"] = fake_fn
    sys.modules["firebase_functions.https_fn"] = fake_https


# --- firebase_admin stub (with both storage and firestore submodules) --------

if "firebase_admin" not in sys.modules:
    fake_admin = types.ModuleType("firebase_admin")
    fake_admin._apps = {}
    fake_admin.initialize_app = lambda *a, **k: None

    fake_firestore = types.ModuleType("firebase_admin.firestore")
    fake_firestore.client = lambda: MagicMock()
    fake_admin.firestore = fake_firestore

    fake_storage = types.ModuleType("firebase_admin.storage")
    fake_storage.bucket = lambda: MagicMock()
    fake_admin.storage = fake_storage

    fake_auth = types.ModuleType("firebase_admin.auth")
    fake_auth.set_custom_user_claims = MagicMock()
    fake_admin.auth = fake_auth

    sys.modules["firebase_admin"] = fake_admin
    sys.modules["firebase_admin.firestore"] = fake_firestore
    sys.modules["firebase_admin.storage"] = fake_storage
    sys.modules["firebase_admin.auth"] = fake_auth
