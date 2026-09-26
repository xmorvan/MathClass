"""Grades the whole corpus through correct_submission with the real Claude.

Not a unit test (it calls the Anthropic API and costs a few cents): run it
by hand after changing the grading pipeline or the prompts.

    cd functions && venv/bin/python tests/grading_benchmark.py

Reads ANTHROPIC_API_KEY from functions/.secret.local. Firestore is never
touched: authorization and persistence are stubbed.
"""

import json
import os
import pathlib
import sys
import time
import types
from concurrent.futures import ThreadPoolExecutor

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "tests"))

# The key can be passed in the environment (e.g. from
# `firebase functions:secrets:access ANTHROPIC_API_KEY`); otherwise it is
# read from functions/.secret.local.
if not os.environ.get("ANTHROPIC_API_KEY"):
    for line in (ROOT / ".secret.local").read_text().splitlines():
        if line.startswith("ANTHROPIC_API_KEY="):
            os.environ["ANTHROPIC_API_KEY"] = line.split("=", 1)[1].strip().strip('"')
os.environ["CLAUDE_PROVIDER"] = "anthropic"

import correct_submission as cs  # noqa: E402
from grading_corpus import CASES  # noqa: E402

cs._persist_correction = lambda **_: None
# Grading context per case, looked up by the submission ID the request
# carries (cases run in parallel threads).
CONTEXTS = {
    case.id: {
        "expected_answer": case.expected,
        "statement": case.statement,
        "notation_strict": False,
        "is_teacher": False,
        "stored_steps": [],
        "stored_attempt": None,
    }
    for case in CASES
}
cs._authorize = lambda _req, submission_id: CONTEXTS[submission_id]


def grade(case):
    request = types.SimpleNamespace(
        data={"submissionID": case.id, "studentSteps": list(case.steps), "attemptNumber": 1},
        auth=None,
    )
    started = time.time()
    fast = cs.sympy_grade_steps(case.expected, list(case.steps)) is not None
    try:
        result = cs.correct_submission_handler(request)
        error = None
    except Exception as exc:  # noqa: BLE001
        result, error = {}, getattr(exc, "message", None) or str(exc)
    return {
        "id": case.id,
        "level": case.level,
        "expected_correct": case.correct,
        "graded_correct": result.get("allCorrect"),
        "steps": result.get("stepResults"),
        "first_error": result.get("firstErrorIndex"),
        "expected_first_error": case.first_error,
        "by": "SymPy" if fast else "Claude",
        "seconds": round(time.time() - started, 1),
        "error": error,
    }


def main():
    with ThreadPoolExecutor(max_workers=6) as pool:
        rows = list(pool.map(grade, CASES))
    wrong = [r for r in rows if r["graded_correct"] != r["expected_correct"]]
    for r in rows:
        mark = "OK " if r["graded_correct"] == r["expected_correct"] else "ERR"
        print(f"{mark} {r['id']:<28} {r['level']:<8} attendu={'juste' if r['expected_correct'] else 'faux':<5} "
              f"note={r['steps']} par {r['by']:<6} {r['seconds']:>5}s {r['error'] or ''}")
    false_accept = [r for r in wrong if not r["expected_correct"]]
    false_reject = [r for r in wrong if r["expected_correct"]]
    print(f"\n{len(rows) - len(wrong)}/{len(rows)} correctes ; "
          f"{len(false_accept)} copie(s) fausse(s) acceptée(s), {len(false_reject)} juste(s) refusée(s).")
    out = pathlib.Path(os.environ.get("BENCH_OUT", "grading_benchmark.json"))
    out.write_text(json.dumps(rows, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
