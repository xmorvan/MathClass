"""Static checks on main.py, the deploy entry point.

Two regressions these guard against:
  - a handler losing its decorator (e.g. in a merge): the function is then
    silently not deployed;
  - the Admin app not being initialised at import: the callable wrapper
    verifies ID tokens before any lazily-imported handler runs, so every
    call on a fresh instance is treated as signed out.
"""

import ast
import pathlib

MAIN = pathlib.Path(__file__).resolve().parent.parent / "main.py"
TREE = ast.parse(MAIN.read_text(encoding="utf-8"))

EXPECTED = {
    "extract_exercise",
    "recognize_handwriting",
    "correct_submission",
    "join_class",
    "claim_student_seat",
    "generate_class_code",
    "delete_student_data",
    "delete_class",
    "delete_account",
    "purge_old_submissions",
}


def _top_level_functions():
    return [n for n in TREE.body if isinstance(n, ast.FunctionDef)]


def test_every_expected_function_is_defined():
    names = {f.name for f in _top_level_functions()}
    assert EXPECTED <= names, f"missing: {EXPECTED - names}"


def test_every_top_level_function_is_a_decorated_cloud_function():
    undecorated = [f.name for f in _top_level_functions() if not f.decorator_list]
    assert undecorated == []


def test_admin_app_is_initialised_at_import():
    source = MAIN.read_text(encoding="utf-8")
    module_level = [
        n for n in TREE.body if isinstance(n, ast.If)
        and "initialize_app" in ast.get_source_segment(source, n)
    ]
    assert module_level, "firebase_admin.initialize_app() must run when main.py is imported"
