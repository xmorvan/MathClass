"""Skill taxonomy, exercise tagging and per-step diagnosis."""

import json
import pathlib
import sys
from unittest.mock import MagicMock

import pytest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))

import correct_submission as cs  # noqa: E402
import tag_exercises as te  # noqa: E402
import taxonomy  # noqa: E402
from conftest import FakeFirestore, make_request, student_auth, teacher_auth  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent


def _answer(payload):
    client = MagicMock()
    client.messages.create.return_value = MagicMock(content=[MagicMock(text=json.dumps(payload))])
    return client


# ── Taxonomy ────────────────────────────────────────────────────────────


def test_app_and_functions_share_the_same_taxonomy():
    """The app bundles its own copy: both come from taxonomy_source.txt."""
    assert (ROOT / "Core/Resources/Taxonomy.json").read_text() == (ROOT / "functions/taxonomy.json").read_text()


def test_taxonomy_is_built_from_its_source():
    sys.path.insert(0, str(ROOT / "tools"))
    import build_taxonomy
    built = build_taxonomy.parse((ROOT / "functions/taxonomy_source.txt").read_text(encoding="utf-8"))
    assert built == taxonomy.load(), "run tools/build_taxonomy.py"


def test_skill_ids_are_three_levels_and_labelled():
    assert len(taxonomy.skills()) > 150
    for skill_id, labels in taxonomy.skills().items():
        assert skill_id.count(".") == 2
        assert all(labels)
    assert taxonomy.is_skill("litteral.developper.trois-facteurs")
    assert not taxonomy.is_skill("litteral.developper")


def test_valid_skills_drops_unknown_and_duplicates():
    assert taxonomy.valid_skills(["x", "litteral.developper.trois-facteurs", "litteral.developper.trois-facteurs"]) == [
        "litteral.developper.trois-facteurs"
    ]


# ── Tagging ─────────────────────────────────────────────────────────────


def test_suggest_skills_keeps_only_catalog_ids():
    client = _answer({"skillIDs": ["litteral.developper.double-distributivite", "made.up.skill"]})
    assert te.suggest_skills(client, "Développer (x+1)(x+2)", "x^2+3x+2") == ["litteral.developper.double-distributivite"]


def test_suggest_skills_never_raises():
    client = MagicMock()
    client.messages.create.side_effect = RuntimeError("down")
    assert te.suggest_skills(client, "Développer (x+1)(x+2)", "") == []


def test_tag_handler_tags_own_untagged_exercises(monkeypatch):
    db = FakeFirestore({
        "exercises/e1": {"teacherID": "teacher-1", "statement": "Développer 3(x+4)", "expectedAnswer": "3x+12"},
        "exercises/e2": {"teacherID": "teacher-1", "statement": "x", "skillIDs": ["litteral.reduire.termes-semblables"]},
    })
    monkeypatch.setattr(te, "_get_firestore", lambda: db)
    monkeypatch.setattr(te.claude_client, "create_client",
                        lambda: _answer({"skillIDs": ["litteral.developper.simple-distributivite"]}))
    monkeypatch.setattr(te.auth_guard, "require_teacher", lambda req: req.auth.uid)
    result = te.tag_exercises_handler(make_request({"exerciseIDs": ["e1", "e2"]}, auth=teacher_auth()))
    assert result["skillIDs"]["e1"] == ["litteral.developper.simple-distributivite"]
    assert db.docs["exercises/e1"]["skillIDs"] == ["litteral.developper.simple-distributivite"]
    assert result["skillIDs"]["e2"] == ["litteral.reduire.termes-semblables"]  # kept


def test_tag_handler_refuses_another_teachers_exercise(monkeypatch):
    db = FakeFirestore({"exercises/e1": {"teacherID": "someone-else", "statement": "x"}})
    monkeypatch.setattr(te, "_get_firestore", lambda: db)
    monkeypatch.setattr(te.claude_client, "create_client", lambda: _answer({}))
    monkeypatch.setattr(te.auth_guard, "require_teacher", lambda req: req.auth.uid)
    with pytest.raises(Exception):
        te.tag_exercises_handler(make_request({"exerciseIDs": ["e1"]}, auth=teacher_auth()))


def test_tag_handler_bounds_its_input(monkeypatch):
    monkeypatch.setattr(te.auth_guard, "require_teacher", lambda req: "teacher-1")
    with pytest.raises(Exception):
        te.tag_exercises_handler(make_request({"exerciseIDs": [f"e{i}" for i in range(21)]}, auth=teacher_auth()))


# ── Diagnosis ───────────────────────────────────────────────────────────


def test_diagnosis_ties_each_wrong_step_to_a_skill():
    client = _answer({"diagnosis": [
        None,
        {"skillID": "litteral.developper.trois-facteurs", "errorType": "algebra",
         "note": "N'a pas distribué le troisième facteur."},
    ]})
    diagnosis = cs._diagnose_errors(client, "Développer (x+1)(x+2)(x+3)", "x^3+6x^2+11x+6",
                                    ["(x+1)(x+2) = x^2+3x+2", "(x^2+3x+2)(x+3) = x^3+3x+2"],
                                    [True, False], ["litteral.developper.trois-facteurs"])
    assert diagnosis[0] is None
    assert diagnosis[1] == {"skillID": "litteral.developper.trois-facteurs", "errorType": "algebra",
                            "note": "N'a pas distribué le troisième facteur."}
    assert cs._error_tags(diagnosis) == [None, "algebra"]


def test_diagnosis_drops_invented_skills_and_types_and_right_steps():
    client = _answer({"diagnosis": [
        {"skillID": "litteral.developper.trois-facteurs", "errorType": "algebra", "note": "x"},
        {"skillID": "not.a.skill", "errorType": "oops", "note": "  "},
    ]})
    diagnosis = cs._diagnose_errors(client, "s", "e", ["a", "b"], [True, False], [])
    assert diagnosis[0] is None  # the step is right: nothing to diagnose
    assert diagnosis[1] == {"skillID": None, "errorType": None, "note": None}


def test_diagnosis_failure_leaves_empty_entries():
    client = MagicMock()
    client.messages.create.side_effect = RuntimeError("down")
    assert cs._diagnose_errors(client, "s", "e", ["a"], [False], []) == [None]


def test_failed_copy_is_diagnosed_and_saved(monkeypatch):
    """Even when SymPy alone grades the copy, the teacher gets the diagnosis."""
    persisted = {}
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test-key")
    monkeypatch.setattr(cs, "_persist_correction", lambda **kw: persisted.update(kw))
    monkeypatch.setattr(cs, "_authorize", lambda req, sid: {
        "expected_answer": "x = 6", "statement": "Résoudre 3x - 7 = 11", "notation_strict": False,
        "is_teacher": False, "stored_steps": [], "stored_attempt": None,
        "skill_ids": ["equations.premier-degre.deux-etapes"],
    })
    client = _answer({"diagnosis": [None, {"skillID": "equations.premier-degre.deux-etapes",
                                           "errorType": "arithmetic", "note": "18 / 3 = 5"}]})
    monkeypatch.setattr(cs.claude_client, "create_client", lambda: client)
    result = cs.correct_submission_handler(make_request(
        {"submissionID": "s1", "studentSteps": ["3x = 18", "x = 5"], "attemptNumber": 1},
        auth=student_auth()))
    assert result["stepResults"] == [True, False]
    assert result["diagnosis"][1]["skillID"] == "equations.premier-degre.deux-etapes"
    assert persisted["diagnosis"][1]["note"] == "18 / 3 = 5"
    assert persisted["error_tags"] == [None, "arithmetic"]


def test_error_in_the_exercise_competency_counts_against_the_exercise_skill():
    client = _answer({"diagnosis": [{"skillID": "litteral.developper.double-distributivite",
                                     "errorType": "algebra", "note": "x"}]})
    diagnosis = cs._diagnose_errors(client, "Développer (x+1)(x-2)(x+3)", "", ["..."], [False],
                                    ["litteral.developper.trois-facteurs"])
    assert diagnosis[0]["skillID"] == "litteral.developper.trois-facteurs"


def test_error_in_a_more_basic_skill_is_kept():
    client = _answer({"diagnosis": [{"skillID": "nombres.relatifs.regle-des-signes",
                                     "errorType": "sign_error", "note": "x"}]})
    diagnosis = cs._diagnose_errors(client, "Résoudre", "", ["..."], [False],
                                    ["equations.premier-degre.deux-etapes"])
    assert diagnosis[0]["skillID"] == "nombres.relatifs.regle-des-signes"


def test_an_incomplete_system_is_diagnosed_as_incomplete(monkeypatch):
    monkeypatch.setenv("ANTHROPIC_API_KEY", "test-key")
    monkeypatch.setattr(cs, "_persist_correction", lambda **kw: None)
    monkeypatch.setattr(cs, "_authorize", lambda req, sid: {
        "expected_answer": r"x = 6 \text{ et } y = 4", "statement": "Système", "notation_strict": False,
        "is_teacher": False, "stored_steps": [], "stored_attempt": None,
        "skill_ids": ["equations.systemes.combinaison"],
    })
    client = _answer({"diagnosis": [None, None]})
    monkeypatch.setattr(cs.claude_client, "create_client", lambda: client)
    monkeypatch.setattr(cs, "sympy_grade_steps", lambda *_: [True, True])
    result = cs.correct_submission_handler(make_request(
        {"submissionID": "s1", "studentSteps": ["2x = 12", "x = 6"], "attemptNumber": 1}, auth=student_auth()))
    assert result["stepResults"] == [True, False]
    assert result["diagnosis"][1] == {"skillID": "equations.systemes.combinaison", "errorType": "incomplete",
                                      "note": "Réponse incomplète : il manque y."}
