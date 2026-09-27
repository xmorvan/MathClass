"""Diagnoses every wrong copy of the corpus with the real Claude, as in
production (the exercise is tagged first, then graded and diagnosed), and
checks the skill named at the first wrong step.

    cd functions && ANTHROPIC_API_KEY=… venv/bin/python tests/diagnosis_benchmark.py
"""

import json
import os
import pathlib
import sys
import types
from concurrent.futures import ThreadPoolExecutor

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "tests"))
os.environ.setdefault("CLAUDE_PROVIDER", "anthropic")

import claude_client  # noqa: E402
import correct_submission as cs  # noqa: E402
import tag_exercises as te  # noqa: E402
from diagnosis_corpus import EXPECTED, EXTRA_CASES  # noqa: E402
from grading_corpus import CASES  # noqa: E402

cs._persist_correction = lambda **_: None
CONTEXTS = {}
cs._authorize = lambda _req, submission_id: CONTEXTS[submission_id]
client = claude_client.create_client()


def run(case):
    skills = te.suggest_skills(client, case.statement, case.expected)
    CONTEXTS[case.id] = {"expected_answer": case.expected, "statement": case.statement, "notation_strict": False,
                         "is_teacher": False, "stored_steps": [], "stored_attempt": None, "skill_ids": skills}
    result = cs.correct_submission_handler(types.SimpleNamespace(
        data={"submissionID": case.id, "studentSteps": list(case.steps), "attemptNumber": 1}, auth=None))
    diagnosis = result.get("diagnosis") or []
    first = result.get("firstErrorIndex")
    entry = diagnosis[first] if first is not None and first < len(diagnosis) else None
    skill = entry.get("skillID") if entry else None
    return {"id": case.id, "exerciseSkills": skills, "skill": skill, "ok": skill in EXPECTED[case.id],
            "expected": sorted(EXPECTED[case.id]),
            "type": entry.get("errorType") if entry else None}


def main():
    cases = [c for c in CASES + EXTRA_CASES if not c.correct]
    with ThreadPoolExecutor(max_workers=6) as pool:
        rows = list(pool.map(run, cases))
    for r in rows:
        if not r["ok"]:
            print(f"ERR {r['id']:<30} → {r['skill']} ({r['type']}) attendu {r['expected']}")
    good = sum(r["ok"] for r in rows)
    print(f"\n{good}/{len(rows)} diagnostics justes ({round(100 * good / len(rows))} %)")
    pathlib.Path(os.environ.get("BENCH_OUT", "diagnosis_benchmark.json")).write_text(
        json.dumps(rows, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
