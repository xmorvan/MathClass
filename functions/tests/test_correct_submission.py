"""
Smoke tests for correct_submission.py (ISSUE-010).

These exercise the parts of the pipeline that can run without network access:
- sympy_check_equivalence over real algebraic identities
- the Phase-1/Phase-2 length-mismatch padding logic (ISSUE-006)
- the persistence retry/surface behaviour (ISSUE-004)

The Anthropic + Firestore calls are mocked. Run with:
    cd functions && python -m pytest tests
"""

from __future__ import annotations

import sys
import types
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

# Make the functions/ directory importable when running from the repo root.
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

# Stub out firebase_functions so the module imports cleanly under pytest.
if "firebase_functions" not in sys.modules:
    fake_fn = types.ModuleType("firebase_functions")

    class _ErrorCode:
        INVALID_ARGUMENT = "invalid-argument"
        INTERNAL = "internal"
        UNAVAILABLE = "unavailable"

    class _HttpsError(Exception):
        def __init__(self, code, message, details=None):
            self.code = code
            self.message = message
            self.details = details
            super().__init__(message)

    fake_https = types.SimpleNamespace(
        FunctionsErrorCode=_ErrorCode,
        HttpsError=_HttpsError,
        on_call=lambda **_: (lambda fn: fn),
        CallableRequest=object,
    )
    fake_fn.https_fn = fake_https
    sys.modules["firebase_functions"] = fake_fn
    sys.modules["firebase_functions.https_fn"] = fake_https

# Same for firebase_admin so _get_firestore can be patched.
if "firebase_admin" not in sys.modules:
    fake_admin = types.ModuleType("firebase_admin")
    fake_admin._apps = {}
    fake_admin.initialize_app = lambda *a, **k: None
    fake_firestore = types.ModuleType("firebase_admin.firestore")
    fake_firestore.client = lambda: MagicMock()
    sys.modules["firebase_admin"] = fake_admin
    sys.modules["firebase_admin.firestore"] = fake_firestore

import correct_submission as cs  # noqa: E402  (after sys.path injection)


# ---------------------------------------------------------------------------
# SymPy equivalence
# ---------------------------------------------------------------------------


def test_sympy_recognises_identity():
    """`x + 1` and `1 + x` should be equivalent."""
    assert cs.sympy_check_equivalence("x + 1", "1 + x") is True


def test_sympy_recognises_expansion():
    """`(x+1)^2` should match `x^2 + 2x + 1` after expand+simplify."""
    assert cs.sympy_check_equivalence("(x+1)^2", "x^2 + 2*x + 1") is True


def test_sympy_recognises_inequivalence():
    """`x + 1` and `x + 2` should not be equivalent."""
    # SymPy may return False or None depending on what it can determine —
    # both are acceptable answers here. None pushes to the Claude fallback,
    # which the orchestration will resolve.
    result = cs.sympy_check_equivalence("x + 1", "x + 2")
    assert result is False or result is None


def test_sympy_returns_none_on_garbage():
    """Unparseable LaTeX should return None (→ Claude fallback)."""
    assert cs.sympy_check_equivalence("\\frob{xyz", "x") is None


# ---------------------------------------------------------------------------
# Phase-1/Phase-2 length-mismatch padding (ISSUE-006)
# ---------------------------------------------------------------------------


def _fake_request(data: dict) -> object:
    return types.SimpleNamespace(data=data)


def _fake_anthropic_with_pairs(pairs: list[dict]):
    """Build a stub anthropic client that returns the given pairs as JSON."""
    import json as _json

    fake_client = MagicMock()

    structuring_response = MagicMock()
    structuring_response.content = [
        MagicMock(text=_json.dumps({"pairs": pairs}))
    ]
    fake_client.messages.create.return_value = structuring_response
    return fake_client


@pytest.fixture(autouse=True)
def _stub_environment(monkeypatch):
    """Set ANTHROPIC_API_KEY and bypass the real persist call by default."""
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test-key")
    # Default: persist succeeds. Individual tests override.
    monkeypatch.setattr(cs, "_persist_correction", lambda **_: None)


def test_handler_pads_short_pair_list_with_false(monkeypatch):
    """Claude returns 1 pair for 3 student steps → tail padded as False."""
    fake_client = _fake_anthropic_with_pairs([
        {
            "studentExpr": "x + 1",
            "referenceExpr": "1 + x",
            "description": "commutativité",
        },
    ])
    monkeypatch.setattr(cs.anthropic, "Anthropic", lambda **_: fake_client)
    monkeypatch.setattr(
        cs,
        "sympy_check_equivalence",
        lambda a, b: True,  # First pair is "correct".
    )

    req = _fake_request({
        "studentSteps": ["x + 1", "x + 2", "x + 3"],
        "expectedAnswer": "x + 3",
        "statement": "Prove the chain.",
        "submissionID": "sub_1",
        "attemptNumber": 1,
    })

    result = cs.correct_submission_handler(req)

    # Length matches studentSteps even though Phase-1 returned only one pair.
    assert len(result["stepResults"]) == 3
    # First step verified True, tail padded False, firstError on the padded
    # head of the tail.
    assert result["stepResults"] == [True, False, False]
    assert result["firstErrorIndex"] == 1
    assert result["allCorrect"] is False


def test_handler_empty_pairs_marks_all_wrong(monkeypatch):
    """When Claude can't structure, every step is marked incorrect."""
    fake_client = _fake_anthropic_with_pairs([])
    monkeypatch.setattr(cs.anthropic, "Anthropic", lambda **_: fake_client)

    req = _fake_request({
        "studentSteps": ["a = b", "b = c"],
        "expectedAnswer": "c",
        "statement": "Foo.",
        "submissionID": "sub_2",
        "attemptNumber": 1,
    })

    result = cs.correct_submission_handler(req)
    assert result["stepResults"] == [False, False]
    assert result["firstErrorIndex"] == 0
    assert result["allCorrect"] is False


# ---------------------------------------------------------------------------
# Persistence failure surfacing (ISSUE-004)
# ---------------------------------------------------------------------------


def test_handler_raises_when_persist_repeatedly_fails(monkeypatch):
    """If the Admin SDK write keeps failing, the callable surfaces UNAVAILABLE."""
    fake_client = _fake_anthropic_with_pairs([
        {"studentExpr": "x", "referenceExpr": "x", "description": ""},
    ])
    monkeypatch.setattr(cs.anthropic, "Anthropic", lambda **_: fake_client)
    monkeypatch.setattr(cs, "sympy_check_equivalence", lambda a, b: True)

    monkeypatch.setattr(
        cs,
        "_persist_correction",
        lambda **_: RuntimeError("firestore down"),
    )

    req = _fake_request({
        "studentSteps": ["x"],
        "expectedAnswer": "x",
        "statement": "Trivial.",
        "submissionID": "sub_3",
        "attemptNumber": 1,
    })

    https_fn = sys.modules["firebase_functions"].https_fn
    with pytest.raises(https_fn.HttpsError) as exc_info:
        cs.correct_submission_handler(req)
    assert exc_info.value.code == https_fn.FunctionsErrorCode.UNAVAILABLE


def test_persist_helper_retries_then_returns_error(monkeypatch):
    """`_persist_correction` retries 3× and returns the last exception."""
    call_count = {"n": 0}

    def fake_get_firestore():
        call_count["n"] += 1
        client = MagicMock()
        client.collection.return_value.document.return_value.update.side_effect = (
            RuntimeError("nope")
        )
        return client

    monkeypatch.setattr(cs, "_get_firestore", fake_get_firestore)
    # Skip the sleep so the test runs fast.
    monkeypatch.setattr(cs.time, "sleep", lambda _x: None)

    err = cs._persist_correction(
        submission_id="x",
        step_results=[True],
        first_error_index=None,
        final_result="success_1st",
    )

    assert isinstance(err, RuntimeError)
    assert call_count["n"] == 3


# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------


def test_handler_rejects_missing_submission_id():
    https_fn = sys.modules["firebase_functions"].https_fn
    req = _fake_request({
        "studentSteps": ["x"],
        "expectedAnswer": "x",
        "statement": "",
        "submissionID": "",
        "attemptNumber": 1,
    })
    with pytest.raises(https_fn.HttpsError):
        cs.correct_submission_handler(req)


def test_handler_rejects_too_many_steps():
    https_fn = sys.modules["firebase_functions"].https_fn
    req = _fake_request({
        "studentSteps": ["x"] * 31,
        "expectedAnswer": "x",
        "statement": "",
        "submissionID": "sub",
        "attemptNumber": 1,
    })
    with pytest.raises(https_fn.HttpsError):
        cs.correct_submission_handler(req)


def test_handler_rejects_invalid_attempt_number():
    https_fn = sys.modules["firebase_functions"].https_fn
    req = _fake_request({
        "studentSteps": ["x"],
        "expectedAnswer": "x",
        "statement": "",
        "submissionID": "sub",
        "attemptNumber": 3,
    })
    with pytest.raises(https_fn.HttpsError):
        cs.correct_submission_handler(req)


def test_handler_returns_empty_for_empty_steps(monkeypatch):
    req = _fake_request({
        "studentSteps": [],
        "expectedAnswer": "x",
        "statement": "",
        "submissionID": "sub",
        "attemptNumber": 1,
    })
    result = cs.correct_submission_handler(req)
    assert result["stepResults"] == []
    assert result["firstErrorIndex"] is None
