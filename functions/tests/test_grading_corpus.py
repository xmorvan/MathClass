"""SymPy alone must never be wrong on the grading corpus: when it decides,
its verdict matches the copy; when it cannot, Claude decides instead."""

import pytest

import correct_submission as cs
from grading_corpus import CASES


@pytest.mark.parametrize("case", CASES, ids=[c.id for c in CASES])
def test_sympy_is_never_wrong_when_it_decides(case):
    pytest.importorskip("sympy")
    cs._ensure_sympy()
    if not cs.SYMPY_AVAILABLE:
        pytest.skip("SymPy LaTeX parser unavailable")
    results = cs.sympy_grade_steps(case.expected, list(case.steps))
    if results is None:
        pytest.skip("left to Claude")
    assert all(results) == case.correct, results
    if not case.correct and case.first_error is not None:
        assert results.index(False) == case.first_error, results
