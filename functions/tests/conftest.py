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
        UNAUTHENTICATED = "unauthenticated"
        PERMISSION_DENIED = "permission-denied"
        NOT_FOUND = "not-found"

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

    sys.modules["firebase_admin"] = fake_admin
    sys.modules["firebase_admin.firestore"] = fake_firestore
    sys.modules["firebase_admin.storage"] = fake_storage


# --- Caller identities and an in-memory Firestore -----------------------------
#
# Used by the authorization tests: `FakeFirestore` implements just the
# Admin SDK surface the handlers touch (document get, subcollections,
# equality `where` + `limit` + `stream`).


def make_request(data, auth=None):
    return types.SimpleNamespace(data=data, auth=auth)


def teacher_auth(uid="teacher-1"):
    return types.SimpleNamespace(
        uid=uid, token={"firebase": {"sign_in_provider": "password"}}
    )


def anonymous_auth(uid="anon-1", **claims):
    token = {"firebase": {"sign_in_provider": "anonymous"}}
    token.update(claims)
    return types.SimpleNamespace(uid=uid, token=token)


def student_auth(class_id="class-1", student_id="stu-1", uid="anon-1"):
    return anonymous_auth(
        uid=uid, role="student", classID=class_id, studentID=student_id
    )


class _Snapshot:
    def __init__(self, doc_id, data):
        self.id = doc_id
        self._data = data
        self.exists = data is not None

    def to_dict(self):
        return dict(self._data) if self._data is not None else None


class _DocumentRef:
    def __init__(self, store, path):
        self._store = store
        self._path = path

    def get(self):
        return _Snapshot(self._path.rsplit("/", 1)[-1], self._store.get(self._path))

    def collection(self, name):
        return _CollectionRef(self._store, f"{self._path}/{name}")


class _CollectionRef:
    def __init__(self, store, path, filters=None, max_results=None):
        self._store = store
        self._path = path
        self._filters = filters or []
        self._limit = max_results

    def document(self, doc_id):
        return _DocumentRef(self._store, f"{self._path}/{doc_id}")

    def where(self, field, op, value):
        assert op == "==", "FakeFirestore only supports equality filters"
        return _CollectionRef(
            self._store, self._path, self._filters + [(field, value)], self._limit
        )

    def limit(self, n):
        return _CollectionRef(self._store, self._path, self._filters, n)

    def stream(self):
        prefix = self._path + "/"
        results = []
        for path, data in sorted(self._store.items()):
            if not path.startswith(prefix) or "/" in path[len(prefix):]:
                continue
            if all(data.get(f) == v for f, v in self._filters):
                results.append(_Snapshot(path[len(prefix):], data))
        return results[: self._limit] if self._limit is not None else results


class FakeFirestore:
    """Documents keyed by full path, e.g. {"classes/c1": {...}}."""

    def __init__(self, docs=None):
        self.docs = dict(docs or {})

    def collection(self, name):
        return _CollectionRef(self.docs, name)
