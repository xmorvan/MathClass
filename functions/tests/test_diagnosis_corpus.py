"""The expected diagnoses name real skills and cover every wrong copy."""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import taxonomy  # noqa: E402
from diagnosis_corpus import EXPECTED, EXTRA_CASES  # noqa: E402
from grading_corpus import CASES  # noqa: E402


def test_every_expected_skill_exists():
    unknown = {s for skills in EXPECTED.values() for s in skills if not taxonomy.is_skill(s)}
    assert not unknown, unknown


def test_every_wrong_copy_has_an_expected_diagnosis():
    wrong = {c.id for c in CASES + EXTRA_CASES if not c.correct}
    assert wrong == set(EXPECTED), (wrong - set(EXPECTED), set(EXPECTED) - wrong)
