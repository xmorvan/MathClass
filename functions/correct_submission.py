"""
correct_submission.py
Cloud Function that implements the hybrid correction pipeline.

Correction process:
1. Receive student LaTeX steps + expected answer + exercise statement
2. Claude Haiku structures step pairs (student_expression, reference_expression)
3. SymPy verifies algebraic equivalence for each pair: simplify(student - ref) == 0
4. If SymPy can't determine → Claude fallback judgment
5. Return CorrectionResult: {stepResults: [true, true, false], firstErrorIndex: 2}
"""

import json
import math
import os
import re
import time
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeoutError

import anthropic
from firebase_functions import https_fn

import auth_guard
import claude_client
import taxonomy
from _helpers import extract_json

# SymPy is imported lazily on first call — `import sympy` alone takes
# several seconds and blows the 10-second Cloud Functions deployment
# introspection timeout when combined with the other heavy imports
# (anthropic, firebase_functions, etc.).
sympy = None
parse_latex = None
SYMPY_AVAILABLE = False


def _ensure_sympy():
    """Lazy-load sympy + parse_latex on first use."""
    global sympy, parse_latex, SYMPY_AVAILABLE
    if sympy is not None:
        return
    try:
        import sympy as _sympy
        from sympy.parsing.latex import parse_latex as _parse_latex

        # parse_latex needs antlr4-python3-runtime, but a missing antlr does
        # not raise on import — it raises the first time parse_latex runs.
        # Probe here so SYMPY_AVAILABLE reflects actual usability.
        _parse_latex("1+1")

        sympy = _sympy
        parse_latex = _parse_latex
        SYMPY_AVAILABLE = True
    except Exception as exc:
        # Loud on purpose: without SymPy every answer is judged by Claude
        # alone, which has accepted wrong final answers.
        print(f"[sympy] UNAVAILABLE, grading falls back to Claude only: {exc}")
        SYMPY_AVAILABLE = False


def _get_firestore():
    """Lazy-load firebase_admin.firestore() — kept off the import path so the
    deployment introspection step doesn't pay for it. Initialises the default
    app if no other handler did so first."""
    import firebase_admin
    from firebase_admin import firestore

    if not firebase_admin._apps:
        firebase_admin.initialize_app()
    return firestore.client()


# System prompt for structuring step pairs (Phase 1 of correction). The
# rules block is static so it can be cached server-side by Anthropic; the
# per-call statement / expected_answer / student_steps go in the user
# message. Switching to system+cache cut the structuring-prompt input
# tokens by ~80 % on warm cache (see ISSUE-014).
STRUCTURING_SYSTEM = """Tu es un correcteur mathématique expert. Tu dois vérifier le travail d'un élève étape par étape.

Ta tâche :
1. Pour chaque étape de l'élève, détermine l'expression mathématique de référence correspondante
   (ce que l'étape DEVRAIT être si elle est correcte dans le contexte du raisonnement).
2. La dernière étape doit aboutir à la réponse attendue.

Réponds UNIQUEMENT avec un JSON valide, sans markdown ni backticks :
{
  "pairs": [
    {
      "studentExpr": "expression LaTeX de l'élève",
      "referenceExpr": "expression LaTeX de référence correcte",
      "description": "brève description de ce que cette étape fait"
    }
  ]
}

Si le travail de l'élève est vide ou incompréhensible :
{
  "pairs": []
}
"""

# System prompt for Claude fallback verification (when SymPy can't decide)
FALLBACK_PROMPT = """Tu es un correcteur de mathématiques. Une étape écrite par un élève est comparée à l'étape attendue.

L'étape de l'élève est JUSTE si elle est mathématiquement vraie et mène au même résultat que l'étape attendue. Ne la pénalise PAS pour :
- une unité absente (« 2500 » au lieu de « 2500 m ») ;
- une autre notation (« S = {{2 ; 3}} » pour « x = 2 ou x = 3 », « : » pour la division, virgule décimale) ;
- moins de détails (l'élève écrit le résultat d'une opération que la référence détaille, ou omet le « ⟹ ») ;
- une constante d'intégration « + C » ajoutée ou omise dans une primitive.
Elle est FAUSSE si elle contient une erreur de calcul, de signe ou de raisonnement, ou si son résultat diffère.

Énoncé de l'exercice : {statement}
Expression de l'élève : {student_expr}
Expression de référence : {reference_expr}
Contexte : {description}

Réponds UNIQUEMENT avec un JSON valide :
{{
  "equivalent": true ou false,
  "reason": "brève explication"
}}
"""


def _run_with_timeout(fn, *args, secs: float = 3.0, **kwargs):
    """Run a SymPy call in a worker thread, raising FutureTimeoutError if it
    runs longer than `secs`. SymPy has no native timeout API and pathological
    expressions (deeply nested radicals, very large polynomials) can simplify
    for minutes — long enough to eat the entire Cloud Functions wall clock.

    SIGALRM would be simpler but isn't safe under Cloud Run (multi-threaded);
    a worker thread is portable.
    """
    with ThreadPoolExecutor(max_workers=1) as pool:
        future = pool.submit(fn, *args, **kwargs)
        return future.result(timeout=secs)


# Separators between alternative solutions: "x = 3 \text{ ou } x = -3".
_SOLUTION_SEPARATORS = re.compile(
    r"\\text\{\s*(?:ou|or|et|and)\s*\}|\\lor|\\vee|\\quad|;|,"
)


def _normalize_french(latex: str) -> str:
    """French school notation to what the LaTeX parser understands: decimal
    commas ("2,5", "2{,}5") become points and ":" between operands is a
    division ("36 : 4")."""
    latex = re.sub(r"(?<=\d)(?:\{,\}|,)(?=\d)", ".", latex)
    return re.sub(r"(?<=[\w)}\]])\s*:\s*(?=[\w(\\{])", r" \\div ", latex)


_IMPLIES = re.compile(r"\\(?:implies|Rightarrow|Longrightarrow|iff|Leftrightarrow)")
# A word or unit, with the exponent of a unit ("\\text{ cm}^2").
_TEXT = re.compile(r"\\(?:text|mathrm)\{\s*([^{}]*?)\s*\}(?:\^\{?\d\}?)?")


_PROBABILITY_NAME = re.compile(r"^\s*[PEV](?:_\{?\w+\}?)?\([^()]*\)\s*=")


def _prepare(latex: str) -> str:
    """What SymPy should read in a line: the last statement after an
    implication, without units or words (kept: "ou"/"et" between
    solutions), in French notation normalised."""
    latex = _IMPLIES.split(latex)[-1]
    # "= 3 \\times 0,125" continues the previous line.
    latex = re.sub(r"^\s*=", "", latex)
    # "P(X = 2) = …", "E(X) = …": a probability name, whose inner "=" or
    # "\\le" is not part of the calculation.
    latex = _PROBABILITY_NAME.sub("", latex)
    # The constant of an antiderivative ("x^3 + \\ln x + C").
    latex = re.sub(r"\+\s*[CK]\s*$", "", latex.rstrip())
    latex = _TEXT.sub(
        lambda m: f"\\text{{ {m.group(1)} }}" if m.group(1).lower() in ("ou", "or", "et", "and") else " ",
        latex,
    )
    return _normalize_french(latex).strip()


def _sides(latex: str):
    """Parsed sides of "a = b = c", or None if one cannot be read."""
    sides = [_parse_or_none(side) for side in latex.split("=")]
    if any(not isinstance(side, sympy.Expr) for side in sides):
        return None
    return sides


def _chain_breaks(latex: str) -> bool:
    """True when two neighbouring sides without unknowns differ
    ("6^2 + 8^2 = 110"): a calculation mistake inside the line."""
    sides = _sides(latex)
    if not sides:
        return False
    for a, b in zip(sides, sides[1:]):
        if not a.free_symbols and not b.free_symbols and _expressions_equal(a, b) is False:
            return True
    return False


def _equation_solutions(latex: str):
    """Solution set of a one-unknown equation, or of alternatives such as
    "x = 3 ou x = -3", as (lower-cased unknown name, frozenset of exact
    values). None when this is not such an equation or SymPy cannot tell.

    Decimals become exact rationals so "x = 0.5" matches "x = \\frac{1}{2}".
    """
    latex = _prepare(latex)
    if latex.count("=") == 0:
        return None
    parts = [part for part in _SOLUTION_SEPARATORS.split(latex) if part.strip()]
    if len(parts) > 1 and all(part.count("=") == 1 for part in parts):
        name = None
        values = set()
        for part in parts:
            equation = parse_latex(part)
            if not isinstance(equation, sympy.Equality) or not isinstance(equation.lhs, sympy.Symbol):
                return None
            if name is not None and equation.lhs.name.lower() != name:
                return None
            name = equation.lhs.name.lower()
            values.add(sympy.nsimplify(equation.rhs, rational=True))
        return name, frozenset(values)
    if len(parts) > 1:
        return None

    # "c^2 = 6^2 + 8^2 = 100" is the equation c^2 = 100 (the chain itself
    # is checked by _chain_breaks).
    sides = _sides(latex)
    if not sides:
        return None
    difference = sympy.nsimplify(sides[0] - sides[-1], rational=True)
    unknowns = difference.free_symbols
    if len(unknowns) != 1:
        return None
    unknown = next(iter(unknowns))
    solutions = _run_with_timeout(sympy.solveset, difference, unknown, sympy.S.Complexes)
    if not isinstance(solutions, sympy.FiniteSet):
        return None
    return unknown.name.lower(), frozenset(solutions)


def _equations_equivalent(student_latex: str, reference_latex: str) -> bool | None:
    """Equations are equivalent when they have the same solutions. A line
    of arithmetic ("2.5 \\times 1000 = 2500") matches a reference line
    with the same result."""
    if _chain_breaks(_prepare(student_latex)):
        return False
    student_sides = _sides(_prepare(student_latex))
    # A line true for every value ("\\frac{(x-2)(x+2)}{x-2} = x + 2") is a
    # correct simplification step, whatever the reference says.
    if student_sides and len(student_sides) >= 2 and any(side.free_symbols for side in student_sides):
        if all(_expressions_equal(a, b) is True for a, b in zip(student_sides, student_sides[1:])):
            return True
    reference_sides = _sides(_prepare(reference_latex)) if "=" in _prepare(reference_latex) else None
    if student_sides and not any(side.free_symbols for side in student_sides):
        if reference_sides and not any(side.free_symbols for side in reference_sides):
            return True if _expressions_equal(student_sides[-1], reference_sides[-1]) else None
        # Against a bare expected value ("9\\pi"), the line's result must
        # be that value.
        if "=" not in _prepare(reference_latex):
            target = _parse_or_none(_prepare(reference_latex))
            if isinstance(target, sympy.Expr) and not target.free_symbols:
                return _expressions_equal(student_sides[-1], target)
        return None
    # "F(x) = x^3 + \\ln x" against "F(x) = x^3 + \\ln(x)": the same name
    # on the left, compare what it is equal to.
    if student_sides and reference_sides and len(student_sides) >= 2 and len(reference_sides) == 2:
        name = reference_sides[0]
        if isinstance(name, sympy.core.function.AppliedUndef) and sympy.srepr(student_sides[0]) == sympy.srepr(name):
            return _expressions_equal(student_sides[-1], reference_sides[1])
    student = _equation_solutions(student_latex)
    reference = _equation_solutions(reference_latex)
    if student is None or reference is None or student[0] != reference[0]:
        return None
    return student[1] == reference[1]


_INEQUALITY = re.compile(r"<|>|\\le|\\ge|\\leq|\\geq|\\leqslant|\\geqslant")


def _inequality_solutions(latex: str):
    """(unknown name, solution set) of a one-unknown inequality, or None."""
    relation = _parse_or_none(_prepare(latex))
    if not isinstance(relation, sympy.core.relational.Relational) or isinstance(relation, sympy.Equality):
        return None
    unknowns = relation.free_symbols
    if len(unknowns) != 1:
        return None
    unknown = next(iter(unknowns))
    try:
        solutions = _run_with_timeout(
            sympy.solveset, sympy.nsimplify(relation, rational=True), unknown, sympy.S.Reals
        )
    except Exception:
        return None
    return unknown.name.lower(), solutions


def _inequalities_equivalent(student_latex: str, reference_latex: str) -> bool | None:
    student = _inequality_solutions(student_latex)
    reference = _inequality_solutions(reference_latex)
    if student is None or reference is None or student[0] != reference[0]:
        return None
    return student[1] == reference[1]


def _canonical_text(latex: str) -> str:
    """The LaTeX without spacing and sizing commands, to spot identical lines."""
    return re.sub(r"\s+|\\left|\\right|\\[,;:!]", "", latex)


def sympy_check_equivalence(student_latex: str, reference_latex: str) -> bool | None:
    """Check algebraic equivalence using SymPy.

    Equations are compared through their solution sets (for one unknown);
    other expressions through simplification of their difference.

    Returns:
        True if equivalent, False if not, None if SymPy can't determine.
    """
    _ensure_sympy()
    if not SYMPY_AVAILABLE:
        return None

    student_latex = _prepare(student_latex)
    reference_latex = _prepare(reference_latex)
    # The same line as the reference, whatever SymPy can read of it.
    if _canonical_text(student_latex) and _canonical_text(student_latex) == _canonical_text(reference_latex):
        return True
    try:
        if _INEQUALITY.search(student_latex) and _INEQUALITY.search(reference_latex):
            return _inequalities_equivalent(student_latex, reference_latex)
        if "=" in student_latex or "=" in reference_latex:
            return _equations_equivalent(student_latex, reference_latex)

        student_expr = _parse_or_none(student_latex)
        reference_expr = _parse_or_none(reference_latex)
        if not isinstance(student_expr, sympy.Expr) or not isinstance(reference_expr, sympy.Expr):
            return None

        # Try direct simplification (timeout-bounded).
        diff = _run_with_timeout(sympy.simplify, student_expr - reference_expr)
        if diff == 0:
            return True

        # Try expanding then simplifying.
        expanded_diff = sympy.expand(student_expr) - sympy.expand(reference_expr)
        diff_expanded = _run_with_timeout(sympy.simplify, expanded_diff)
        if diff_expanded == 0:
            return True

        # Try trigonometric simplification.
        diff_trig = _run_with_timeout(sympy.trigsimp, student_expr - reference_expr)
        if diff_trig == 0:
            return True

        # If simplification gives a non-zero constant, they're definitely not equal
        if diff.is_number and diff != 0:
            return False

        # SymPy can't determine — return None for Claude fallback
        return None

    except FutureTimeoutError:
        # SymPy ran past the per-call budget — treat as undecidable so the
        # Claude fallback takes over. Logged so the slow expression is visible
        # in Cloud Logging if it recurs.
        print(
            f"[sympy] simplify timed out after 3s; "
            f"student={student_latex[:80]!r} reference={reference_latex[:80]!r}"
        )
        return None
    except Exception as exc:
        # Parse error, missing antlr, or unsupported expression — fall back to
        # Claude. Logging so a missing antlr at deploy time is visible (without
        # this, every step paid for an extra Claude round-trip silently).
        print(f"[sympy] check failed: {exc}")
        return None


# ---------------------------------------------------------------------------
# SymPy-first grading: no AI when every step can be checked exactly
# ---------------------------------------------------------------------------

def _parse_or_none(latex: str):
    try:
        parsed = parse_latex(latex)
    except Exception:
        return None
    # The LaTeX parser reads \\pi as a variable named "pi".
    pi = sympy.Symbol("pi")
    if hasattr(parsed, "free_symbols") and pi in parsed.free_symbols:
        parsed = parsed.subs(pi, sympy.pi)
    # Written decimals are exact: 1 - 0.3 is 0.7, not 0.7000000000000001.
    if isinstance(parsed, sympy.Basic):
        floats = parsed.atoms(sympy.Float)
        if floats:
            parsed = parsed.xreplace({f: sympy.Rational(str(f)) for f in floats})
    return parsed


def _is_isolated(latex: str) -> bool:
    """True for a finished answer such as "x = 4", "x = \\frac{8}{2} = 4"
    or "x = 3 ou x = -3"."""
    parts = [part for part in _SOLUTION_SEPARATORS.split(latex) if part.strip()]
    for part in parts:
        sides = _sides(part)
        if not sides or len(sides) < 2:
            return False
        if not isinstance(sides[0], sympy.Symbol) or sides[-1].free_symbols:
            return False
    return bool(parts)


def _expressions_equal(a, b) -> bool | None:
    try:
        difference = _run_with_timeout(sympy.simplify, sympy.nsimplify(a - b, rational=True))
    except Exception:
        return None
    if difference == 0:
        return True
    if difference.is_number:
        return False
    return None


# The name of a quantity: P(A), P_B(A), E(X), u_{10}, f'(2), |z|, \\Delta.
# \\ln(4) or \\sin(x) are calculations, not names.
_LABEL = re.compile(
    r"^\s*(?:\|[^|=]+\||(?!\\?(?:ln|log|exp|sin|cos|tan|sqrt|frac|lim|int|sum)\b)\\?[A-Za-z]+'*(?:_\{?[^=\s{}]+\}?)?(?:\([^=]*\))?)\s*$"
)


def sympy_grade_steps(expected_answer: str, steps: list[str]) -> list[bool] | None:
    """Grade every step with SymPy alone, or return None when any step (or
    the expected answer) is outside what SymPy can decide.

    Equation exercises: a step is right when it has the same solutions as the
    expected answer, and the last step must state the answer (x isolated).
    Expression exercises (develop, reduce, factor…): a step is right when
    every side of it equals the expected expression, and the last step must
    have the expected form, not just the same value.
    """
    _ensure_sympy()
    if not SYMPY_AVAILABLE or not steps or not expected_answer.strip():
        return None
    expected_answer = _prepare(expected_answer)
    steps = [_prepare(step) for step in steps]
    try:
        if _INEQUALITY.search(expected_answer):
            expected = _inequality_solutions(expected_answer)
            if expected is None:
                return None
            results = []
            for step in steps:
                solutions = _inequality_solutions(step)
                if solutions is None:
                    return None
                results.append(solutions == expected)
            return results
        if "=" in expected_answer:
            expected = _equation_solutions(expected_answer)
            if expected is None:
                return None
            results: list[bool] = []
            for step in steps:
                if _chain_breaks(step):
                    results.append(False)
                    continue
                solutions = _equation_solutions(step)
                if solutions is None:
                    return None
                if solutions[0] != expected[0]:
                    # Another quantity ("\\Delta = 16", "x_1 = -1"): an
                    # intermediate result SymPy cannot place in the method.
                    return None
                results.append(solutions[1] == expected[1])
            if results[-1] and _is_isolated(expected_answer) and not _is_isolated(steps[-1]):
                results[-1] = False
            return results

        target = _parse_or_none(expected_answer)
        if not isinstance(target, sympy.Expr):
            return None
        results = []
        for step in steps:
            written_sides = step.split("=")
            # "P(\\overline{A}) = 1 - 0,3 = 0,7", "u_{10} = 35": the first
            # side names the quantity asked for, it is not a calculation.
            if len(written_sides) > 1 and not target.free_symbols and _LABEL.match(written_sides[0]):
                written_sides = written_sides[1:]
            sides = [_parse_or_none(side) for side in written_sides]
            if any(not isinstance(side, sympy.Expr) for side in sides):
                return None
            # A line whose sides differ ("3 \\times 12 = 37") is a certain
            # mistake, whatever the exercise.
            if any(_expressions_equal(a, b) is False for a, b in zip(sides, sides[1:])):
                results.append(False)
                continue
            verdicts = [_expressions_equal(side, target) for side in sides]
            if all(verdict is True for verdict in verdicts):
                results.append(True)
                continue
            # A true line worth something else is a correct intermediate
            # result in a word problem ("3 \\times 12 = 36" on the way to
            # 41) but a wrong answer when asked to expand: only the
            # statement tells, so Claude decides.
            return None
        if results[-1]:
            last = _parse_or_none(steps[-1].split("=")[-1])
            # Same value but another form (e.g. left expanded when asked to
            # factor): SymPy cannot tell which form the exercise asks for.
            if last is None or sympy.srepr(last) != sympy.srepr(target):
                return None
        return results
    except FutureTimeoutError:
        return None
    except Exception as exc:
        print(f"[sympy] fast grading failed: {exc}")
        return None


_SCIENTIFIC = re.compile(r"^-?(\d+(?:\.\d+)?)\s*\\(?:times|cdot)\s*10\^\{?-?\d+\}?$")
_FRACTION = re.compile(r"^-?\\[dt]?frac\{\s*(\d+)\s*\}\{\s*(\d+)\s*\}$")


def _stated_values(latex: str) -> dict:
    """{unknown name: value} for each "name = value" a line states
    ("x = 6", "y = 10 - 6 = 4", "x = 6 et y = 4")."""
    stated = {}
    for part in _SOLUTION_SEPARATORS.split(_prepare(latex)):
        sides = _sides(part) if part.count("=") >= 1 else None
        if sides and isinstance(sides[0], sympy.Symbol) and not sides[-1].free_symbols:
            stated.setdefault(sides[0].name.lower(), []).append(sides[-1])
    return stated


def answer_is_incomplete(expected_answer: str, steps: list) -> bool:
    return bool(missing_unknowns(expected_answer, steps))


def missing_unknowns(expected_answer: str, steps: list) -> list:
    """True when the expected answer gives several unknowns (x = 6 et
    y = 4) and the work never states one of them: "x = 6" alone answers
    half of the system."""
    _ensure_sympy()
    if not SYMPY_AVAILABLE:
        return []
    try:
        expected = [p for p in _SOLUTION_SEPARATORS.split(_prepare(expected_answer)) if p.strip()]
        if len(expected) < 2:
            return []
        wanted = []
        for part in expected:
            sides = _sides(part) if "=" in part else None
            if not sides or len(sides) != 2 or not isinstance(sides[0], sympy.Symbol) or sides[1].free_symbols:
                return []  # not a list of values: nothing to check
            wanted.append((sides[0].name.lower(), sides[1]))
        # Alternatives for one unknown (x = 2 ou x = 3) are compared as
        # solution sets elsewhere; here, several unknowns (a system).
        if len({name for name, _ in wanted}) < 2:
            return []
        # An answer given as a set, S = {(6 ; 4)}, is left to the other checks.
        if any("\\{" in step or re.search(r"\bS\s*=", step) for step in steps):
            return []
        stated: dict = {}
        for step in steps:
            for name, values in _stated_values(step).items():
                stated.setdefault(name, []).extend(values)
        return [
            name for name, value in wanted
            if not any(_expressions_equal(value, candidate) is True for candidate in stated.get(name, []))
        ]
    except Exception:  # noqa: BLE001 — a check that cannot run blocks nothing
        return []


def final_form_is_wrong(statement: str, last_step: str) -> bool:
    """True when the statement asks for a form the final answer does not
    have, although its value may be right: factorise, simplify a fraction,
    scientific notation, expand. Value checks cannot see this ("x^2 - 3^2"
    equals the expected factorised form)."""
    _ensure_sympy()
    if not SYMPY_AVAILABLE:
        return False
    task = statement.lower()
    answer = _prepare(last_step).split("=")[-1].strip()
    if not answer:
        return False
    if "notation scientifique" in task:
        match = _SCIENTIFIC.match(answer)
        return not (match and 1 <= float(match.group(1)) < 10)
    if "factoris" in task:
        parsed = _parse_or_none(answer)
        return isinstance(parsed, sympy.Add)
    if "simplifi" in task or "irréductible" in task:
        match = _FRACTION.match(answer)
        return bool(match) and math.gcd(int(match.group(1)), int(match.group(2))) != 1
    if "développ" in task or "developp" in task:
        return "(" in answer.replace("\\left(", "(")
    return False


def claude_check_equivalence(
    client,
    student_expr: str,
    reference_expr: str,
    description: str,
    statement: str = "",
) -> bool:
    """Fallback equivalence check using Claude when SymPy can't determine.
    The statement gives the values a line may use ("u_0 = 5").

    Returns:
        True if Claude considers the expressions equivalent, False otherwise.
    """
    prompt = FALLBACK_PROMPT.format(
        student_expr=student_expr,
        reference_expr=reference_expr,
        description=description,
        statement=statement or "(non fourni)",
    )

    message = client.messages.create(
        model=claude_client.model_id(),
        max_tokens=256,
        temperature=0,
        messages=[{"role": "user", "content": prompt}],
    )

    try:
        result = extract_json(message.content[0].text)
        return bool(result.get("equivalent", False))
    except json.JSONDecodeError:
        return False


# Fixed taxonomy of notation issues. The Cloud Function returns a key from
# this set (or null) so the iOS client can localize it; this used to be a
# free-form French phrase, which the iOS client rendered raw and broke the
# bilingual mandate (ISSUE-014).
NOTATION_KEYS = {
    "missing_brackets",       # negatives without parentheses, e.g. -x written as -x in 2*-x
    "decimal_separator",      # comma vs period (3,14 vs 3.14)
    "implicit_multiplication", # 2x ambiguous, missing \cdot
    "missing_unit",           # numeric answer with no unit when expected
    "ambiguous_fraction",     # 1/2x — is it (1/2)x or 1/(2x)?
    "power_notation",         # x*x written as xx instead of x^2
}

NOTATION_SYSTEM = """Tu es un correcteur mathématique vétilleux sur la notation, mais juste sur le fond.

Ta tâche : examiner les étapes de l'élève et détecter UN problème de notation parmi cette liste fermée :
- "missing_brackets" : un signe négatif sans parenthèses, par ex. 2*-3 au lieu de 2*(-3).
- "decimal_separator" : virgule et point mélangés ou utilisés contre la convention.
- "implicit_multiplication" : multiplication implicite ambiguë (2x au lieu de 2·x quand le contexte l'exige).
- "missing_unit" : réponse numérique sans unité quand une est attendue.
- "ambiguous_fraction" : fraction écrite 1/2x sans parenthèses.
- "power_notation" : x*x écrit au lieu de x^2 (ou similaire).

NE COMMENTE PAS la justesse mathématique — uniquement la forme.

Réponds UNIQUEMENT en JSON, sans markdown :
{
  "key": "missing_brackets" | "decimal_separator" | "implicit_multiplication" | "missing_unit" | "ambiguous_fraction" | "power_notation" | null
}

Si tu ne vois aucun problème de notation, retourne {"key": null}.
"""


def _detect_notation_issue(
    client,
    student_steps: list,
    statement: str,
) -> str | None:
    """Run a Claude pass that flags notation problems separately from
    algebraic correctness. Returns one of the NOTATION_KEYS or None.

    The key is language-neutral — the iOS client looks up a localized
    string in `Localizations.swift` keyed on `notation_note_<key>`.
    Errors are swallowed — notation feedback is best-effort.
    """
    try:
        formatted = "\n".join([f"Étape {i + 1}: {s}" for i, s in enumerate(student_steps)])
        user = f"Énoncé : {statement or '(sans énoncé)'}\nÉtapes :\n{formatted}"
        message = client.messages.create(
            model=claude_client.model_id(),
            max_tokens=64,
            temperature=0,
            system=[
                {
                    "type": "text",
                    "text": NOTATION_SYSTEM,
                    "cache_control": {"type": "ephemeral"},
                }
            ],
            messages=[{"role": "user", "content": user}],
        )
        try:
            data = extract_json(message.content[0].text)
        except json.JSONDecodeError:
            return None
        key = data.get("key")
        if not isinstance(key, str) or key not in NOTATION_KEYS:
            return None
        return key
    except Exception as exc:
        print(f"[correct_submission] notation pass failed: {exc}")
        return None


DIAGNOSIS_SYSTEM = """Tu es un professeur de mathématiques qui diagnostique les erreurs d'un élève pour son enseignant.

Référentiel de savoir-faire (identifiant — Domaine › Compétence › Savoir-faire) :
{catalog}

Types d'erreur : sign_error (signe perdu ou inversé), arithmetic (erreur de calcul numérique), algebra (règle algébrique mal appliquée), method (mauvaise méthode, étape sautée), conceptual (notion mal comprise), incomplete (réponse partielle : une solution oubliée, pas de conclusion), notation (écriture incorrecte), misread (énoncé mal lu, mauvaises données), consequence (étape correctement déduite d'une étape fausse précédente).

Pour CHAQUE étape marquée ERREUR, donne :
- "skillID" : le savoir-faire du référentiel qui a échoué dans CETTE étape. Si l'erreur survient en appliquant un savoir-faire visé par l'exercice, c'est ce savoir-faire (en développant (x²−x−2)(x+3) dans un exercice sur (x+1)(x−2)(x+3) : le produit de trois facteurs). Si elle relève d'un savoir-faire plus élémentaire, choisis celui-ci (signe perdu en déplaçant un terme : transposer dans une équation ; erreur de table : multiplier).
- "errorType" : un des types ci-dessus. Si l'étape est une conséquence logique correcte d'une étape fausse précédente, errorType = "consequence" et skillID = null : ce n'est pas une nouvelle lacune.
- "note" : UNE phrase de 20 mots au plus, pour l'enseignant, qui cite ce que l'élève a écrit (ex. « 3(x + 4) = 3x + 4 : 3 distribué sur x seulement »).

Réponds UNIQUEMENT en JSON, une entrée par étape, null pour les étapes justes :
{{"diagnosis": [null, {{"skillID": "...", "errorType": "...", "note": "..."}}]}}"""


def _diagnose_errors(
    client,
    statement: str,
    expected_answer: str,
    student_steps: list,
    step_results: list,
    exercise_skills: list,
) -> list:
    """For each wrong step, the skill that failed, how, and a note for the
    teacher: [None | {skillID, errorType, note}] of len(student_steps).
    Best effort: a failure leaves the entries empty."""
    n = len(student_steps)
    try:
        lines = [
            f"Étape {i + 1} ({'OK' if i < len(step_results) and step_results[i] else 'ERREUR'}) : {student_steps[i]}"
            for i in range(n)
        ]
        exercise_skill_lines = "\n".join(
            f"- {skill_id} — {' › '.join(taxonomy.skills()[skill_id])}"
            for skill_id in exercise_skills if taxonomy.is_skill(skill_id)
        ) or "(non étiqueté)"
        message = client.messages.create(
            model=claude_client.model_id(),
            max_tokens=700,
            temperature=0,
            system=[{
                "type": "text",
                "text": DIAGNOSIS_SYSTEM.format(catalog=taxonomy.catalog_text()),
                "cache_control": {"type": "ephemeral"},
            }],
            messages=[{
                "role": "user",
                "content": (
                    f"Exercice : {statement}\n"
                    f"Réponse attendue : {expected_answer}\n"
                    f"Savoir-faire visés par l'exercice :\n{exercise_skill_lines}\n\n"
                    f"Travail de l'élève :\n" + "\n".join(lines)
                ),
            }],
        )
        entries = extract_json(message.content[0].text).get("diagnosis") or []
    except Exception as exc:  # noqa: BLE001 — diagnosis is best effort
        print(f"[correct_submission] diagnosis failed: {exc}")
        entries = []

    diagnosis: list = []
    for i in range(n):
        entry = entries[i] if i < len(entries) else None
        wrong = not (i < len(step_results) and step_results[i])
        if not wrong or not isinstance(entry, dict):
            diagnosis.append(None)
            continue
        skill_id = _exercise_skill_in_same_competency(entry.get("skillID"), exercise_skills)
        error_type = entry.get("errorType")
        note = entry.get("note")
        diagnosis.append({
            "skillID": skill_id if taxonomy.is_skill(skill_id) else None,
            "errorType": error_type if error_type in taxonomy.ERROR_TYPES else None,
            "note": note.strip()[:300] if isinstance(note, str) and note.strip() else None,
        })
    return diagnosis


def _exercise_skill_in_same_competency(skill_id, exercise_skills: list):
    """An error made while practising the exercise's skill counts against
    that skill: in "expand (x+1)(x−2)(x+3)", a slip in one of the double
    products is a failure at expanding three factors, not at double
    distributivity."""
    if not taxonomy.is_skill(skill_id) or skill_id in exercise_skills:
        return skill_id
    competency = skill_id.rsplit(".", 1)[0]
    for exercise_skill in exercise_skills:
        if taxonomy.is_skill(exercise_skill) and exercise_skill.rsplit(".", 1)[0] == competency:
            return exercise_skill
    return skill_id


def _error_tags(diagnosis: list) -> list:
    """The per-step error categories older clients read (errorTags)."""
    return [entry.get("errorType") if entry else None for entry in diagnosis]


def _persist_correction(
    submission_id: str,
    step_results: list[bool],
    first_error_index: int | None,
    final_result: str,
    notation_note_key: str | None = None,
    error_tags: list | None = None,
    diagnosis: list | None = None,
) -> Exception | None:
    """Write the correction result to /submissions/{id} via Admin SDK.

    Retries up to 3 times with short backoff. Returns None on success, or
    the last raised exception so the caller can decide whether to surface
    a failure to the client (ISSUE-004).
    """
    last_error: Exception | None = None
    for attempt in range(3):
        try:
            db = _get_firestore()
            doc: dict = {
                "correctionResult": {
                    "stepResults": step_results,
                    "firstErrorIndex": first_error_index,
                },
                "finalResult": final_result,
            }
            if notation_note_key is not None:
                doc["correctionResult"]["notationNoteKey"] = notation_note_key
            if error_tags is not None:
                doc["correctionResult"]["errorTags"] = error_tags
            if diagnosis is not None:
                doc["correctionResult"]["diagnosis"] = diagnosis
            db.collection("submissions").document(submission_id).update(doc)
            return None
        except Exception as e:  # noqa: BLE001 — retry any failure
            last_error = e
            print(
                f"[correct_submission] Firestore persist attempt "
                f"{attempt + 1}/3 failed for {submission_id}: {e}"
            )
            time.sleep(0.4 * (attempt + 1))
    return last_error


def _is_student_caller(req: https_fn.CallableRequest) -> bool:
    token = getattr(getattr(req, "auth", None), "token", None) or {}
    return token.get("role") == "student"


def _authorize(req: https_fn.CallableRequest, submission_id: str) -> dict:
    """Check that the caller may grade the submission.

    Callers are the student who owns it, or the teacher who owns its class
    (to grade work whose background correction never ran, e.g. the iPad
    was closed during an evaluation).

    Returns the grading context read from Firestore (expected answer,
    statement, notation strictness, and the stored steps and attempt
    number) so the client cannot change what it is graded against.
    """
    is_student = _is_student_caller(req)
    identity = auth_guard.require_student(req) if is_student else None
    teacher_uid = None if is_student else auth_guard.require_teacher(req)
    db = _get_firestore()

    submission = db.collection("submissions").document(submission_id).get()
    if not submission.exists:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.NOT_FOUND,
            message="Soumission introuvable.",
        )
    submission_data = submission.to_dict() or {}

    if identity is not None:
        if submission_data.get("studentID") != identity.student_id:
            raise auth_guard._denied()
        class_id = identity.class_id
    else:
        class_id = submission_data.get("classID")
        if not isinstance(class_id, str) or not class_id:
            raise auth_guard._denied()

    class_doc = db.collection("classes").document(class_id).get()
    class_data = (class_doc.to_dict() or {}) if class_doc.exists else {}
    if teacher_uid is not None and class_data.get("teacherID") != teacher_uid:
        raise auth_guard._denied()

    exercise_id = submission_data.get("exerciseID")
    exercise = (
        db.collection("exercises").document(exercise_id).get()
        if isinstance(exercise_id, str) and exercise_id
        else None
    )
    if exercise is None or not exercise.exists:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.NOT_FOUND,
            message="Exercice introuvable.",
        )
    exercise_data = exercise.to_dict() or {}
    notation_strict = class_data.get("notationStrict")

    return {
        "expected_answer": exercise_data.get("expectedAnswer", ""),
        "statement": exercise_data.get("statement", ""),
        "skill_ids": exercise_data.get("skillIDs") or [],
        # Legacy classes without the field default to strict.
        "notation_strict": True if notation_strict is None else bool(notation_strict),
        "is_teacher": teacher_uid is not None,
        "stored_steps": submission_data.get("latexSteps") or [],
        "stored_attempt": submission_data.get("attemptNumber"),
    }


def _join_continuations(steps: list) -> list:
    """A line starting with "=" continues the previous one: prefix it with
    that line's last side, so "= 6 + i - 1" becomes "6 - 2i + 3i - i^2 =
    6 + i - 1" and a step that does not follow from the previous is seen."""
    joined: list = []
    for step in steps:
        if isinstance(step, str) and step.lstrip().startswith("=") and joined and isinstance(joined[-1], str):
            previous = _IMPLIES.split(joined[-1])[-1].split("=")[-1].strip()
            if previous:
                step = f"{previous} {step.lstrip()}"
        joined.append(step)
    return joined


def _warm_up() -> None:
    """Load what the first correction on an instance would otherwise load:
    the Firestore client and the SymPy LaTeX parser."""
    _get_firestore()
    sympy_grade_steps("x=1", ["x+1=2", "x=1"])


def _as_int(value):
    """Read an integer sent by a callable client. The Apple Functions SDK
    sends a Swift `Int` as {"@type": ".../google.protobuf.Int64Value",
    "value": "1"}; accept that form as well as plain numbers."""
    if isinstance(value, dict) and "value" in value:
        value = value["value"]
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)) and float(value).is_integer():
        return int(value)
    if isinstance(value, str) and value.strip().lstrip("-").isdigit():
        return int(value.strip())
    return None


def correct_submission_handler(req: https_fn.CallableRequest) -> dict:
    """Handle the correct_submission Cloud Function call.

    Args:
        req.data:
            - studentSteps: list of LaTeX strings (student's work)
            - submissionID: Firestore document ID — the function will patch
              correctionResult + finalResult on this doc via Admin SDK.
              The caller must be the student who owns it (custom claims)
              or the teacher who owns its class; the rules forbid clients
              from writing correction results.
            - expectedAnswer / statement / notationStrict: ignored. They are
              read from the exercise and class documents instead.
            - attemptNumber: 1 or 2 (used to compute success_1st vs success_2nd).
            A teacher call only needs submissionID: steps and attempt
            number are read from the submission.

    Returns:
        dict with:
            - stepResults: list of booleans (true = correct per step)
            - firstErrorIndex: int or null (index of first wrong step)
            - allCorrect: boolean (shortcut)

    Raises:
        https_fn.HttpsError on validation or processing failures.
    """
    if not req.data:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="Aucune donnée fournie.",
        )

    # The iPad sends a warm-up call when an exercise opens, so the instance
    # has started and loaded SymPy and the LaTeX parser by the time the
    # student asks for a correction (a cold start cost 8–25 s).
    if req.data.get("warmup") is True:
        if getattr(req, "auth", None) is None:
            raise auth_guard._denied()
        _warm_up()
        return {"warm": True}

    submission_id = req.data.get("submissionID")
    if not isinstance(submission_id, str) or not submission_id:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="'submissionID' est requis.",
        )

    # Grade against the exercise stored in Firestore, not against whatever
    # expected answer the client sent. A teacher grades what the student
    # submitted, as stored.
    context = _authorize(req, submission_id)
    expected_answer = context["expected_answer"]
    statement = context["statement"]
    notation_strict = context["notation_strict"]
    if context["is_teacher"]:
        student_steps = context["stored_steps"]
        # Levels mode can store attempt 3+; only first-try vs later matters.
        stored_attempt = _as_int(context["stored_attempt"]) or 1
        attempt_number = 1 if stored_attempt <= 1 else 2
    else:
        student_steps = req.data.get("studentSteps", [])
        attempt_number = _as_int(req.data.get("attemptNumber"))

    if not isinstance(student_steps, list):
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="'studentSteps' doit être une liste.",
        )

    # Bound the input — a runaway list would burn Anthropic credits and
    # blow the 60s function timeout (ISSUE-013).
    if len(student_steps) > 30:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="Trop d'étapes (maximum 30).",
        )

    if attempt_number not in (1, 2):
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="'attemptNumber' doit être 1 ou 2.",
        )

    if not student_steps:
        return {
            "stepResults": [],
            "firstErrorIndex": None,
            "allCorrect": False,
        }

    # "= 6 + i - 1" continues the line above: grade it with what it
    # claims to be equal to.
    student_steps = _join_continuations(student_steps)

    # Claude client for the configured provider (Vertex AI in Europe by
    # default, see claude_client.py).
    client = claude_client.create_client()

    # The notation note does not depend on the grading: ask for it now so
    # it runs while the steps are graded instead of after.
    notation_pool = ThreadPoolExecutor(max_workers=1)
    notation_future = (
        notation_pool.submit(_detect_notation_issue, client, student_steps, statement)
        if notation_strict else None
    )
    notation_pool.shutdown(wait=False)

    # Exact grading first: when SymPy can check every step against the
    # teacher's answer, no AI call is needed (under a second instead of
    # several Claude round-trips).
    fast_results = sympy_grade_steps(expected_answer, student_steps)

    try:
        if fast_results is not None:
            pairs = []
            step_results = fast_results
            first_error_index = next((i for i, ok in enumerate(step_results) if not ok), None)
            all_correct = all(step_results)
            print(f"[correct_submission] graded by SymPy alone: {step_results}")
        else:

            # Phase 1: Use Claude to structure step pairs
            formatted_steps = "\n".join(
                [f"Étape {i + 1}: {step}" for i, step in enumerate(student_steps)]
            )

            # Cache the static prefix of the structuring prompt — the only
            # per-call dynamic parts are the statement, expected answer, and
            # the student's steps. Sending the rules block as a cache-eligible
            # system message cuts ~80 % of the input tokens on warm cache.
            structuring_user = (
                f"Exercice :\n{statement}\n\n"
                f"Réponse attendue : {expected_answer}\n\n"
                f"Travail de l'élève (étapes LaTeX) :\n{formatted_steps}"
            )

            message = client.messages.create(
                model=claude_client.model_id(),
                max_tokens=2048,
                temperature=0,
                system=[
                    {
                        "type": "text",
                        "text": STRUCTURING_SYSTEM,
                        "cache_control": {"type": "ephemeral"},
                    }
                ],
                messages=[{"role": "user", "content": structuring_user}],
            )

            try:
                structured = extract_json(message.content[0].text)
            except json.JSONDecodeError:
                raise https_fn.HttpsError(
                    code=https_fn.FunctionsErrorCode.INTERNAL,
                    message="Impossible de parser la structuration des étapes.",
                )

            pairs = structured.get("pairs", [])

            if not pairs:
                # Claude couldn't structure the steps — all marked as incorrect
                step_results = [False] * len(student_steps)
                first_error_index = 0
                all_correct = False
            else:
                # Phase 2: Verify each step pair.
                # ISSUE-006: Claude can return fewer pairs than studentSteps. Pair
                # by index up to the shorter list and treat any unpaired tail as
                # "could not verify" → False (counts as wrong, conservative). This
                # keeps len(stepResults) == len(studentSteps), which the iOS
                # client relies on when rendering per-step marks.
                step_results: list[bool] = []
                first_error_index: int | None = None

                paired_count = min(len(pairs), len(student_steps))
                # SymPy first; the pairs it cannot decide go to Claude all
                # at once rather than one after the other.
                verdicts: list = [
                    sympy_check_equivalence(pair.get("studentExpr", ""), pair.get("referenceExpr", ""))
                    for pair in pairs[:paired_count]
                ]
                undecided = [i for i, verdict in enumerate(verdicts) if verdict is None]
                if undecided:
                    with ThreadPoolExecutor(max_workers=min(len(undecided), 8)) as pool:
                        answers = pool.map(
                            lambda i: claude_check_equivalence(
                                client,
                                pairs[i].get("studentExpr", ""),
                                pairs[i].get("referenceExpr", ""),
                                pairs[i].get("description", ""),
                                statement,
                            ),
                            undecided,
                        )
                        for i, answer in zip(undecided, answers):
                            verdicts[i] = answer
                for i, is_correct in enumerate(verdicts):
                    step_results.append(bool(is_correct))
                    if not is_correct and first_error_index is None:
                        first_error_index = i

                # Pad any unpaired tail as wrong + log so the mismatch is visible.
                if paired_count < len(student_steps):
                    missing = len(student_steps) - paired_count
                    print(
                        f"[correct_submission] Phase-1 pair shortfall: "
                        f"{paired_count} pairs vs {len(student_steps)} student steps "
                        f"(padding {missing} as incorrect)"
                    )
                    for i in range(paired_count, len(student_steps)):
                        step_results.append(False)
                        if first_error_index is None:
                            first_error_index = i

                # The reference steps come from Claude, which can pair a wrong
                # final answer with itself. When SymPy can compare the last step
                # with the teacher's expected answer, its verdict wins.
                if step_results and step_results[-1]:
                    final_matches = sympy_check_equivalence(student_steps[-1], expected_answer)
                    if final_matches is False:
                        print(
                            f"[correct_submission] final step {student_steps[-1][:60]!r} "
                            f"does not match expected {expected_answer[:60]!r}"
                        )
                        step_results[-1] = False
                        if first_error_index is None:
                            first_error_index = len(step_results) - 1

                all_correct = all(step_results)

        # Every part of a multi-part answer must be given: "x = 6" alone
        # does not solve a system whose answer is x = 6 et y = 4.
        missing = missing_unknowns(expected_answer, student_steps) if step_results and step_results[-1] else []
        if missing:
            print(f"[correct_submission] incomplete answer for {expected_answer[:60]!r}: {missing}")
            step_results[-1] = False
            if first_error_index is None:
                first_error_index = len(step_results) - 1
            all_correct = False

        # The value can be right while the requested form is not
        # ("\\frac{9}{12}" when asked to simplify).
        if step_results and step_results[-1] and final_form_is_wrong(statement, student_steps[-1]):
            print(f"[correct_submission] final answer not in the requested form: {student_steps[-1][:60]!r}")
            step_results[-1] = False
            if first_error_index is None:
                first_error_index = len(step_results) - 1
            all_correct = False

        # Persist the correction result on the submission doc using the
        # Admin SDK so it bypasses firestore.rules (the rule on submissions
        # update is `isTeacher()`, and students have no Firebase Auth).
        if all_correct:
            final_result = "success_1st" if attempt_number == 1 else "success_2nd"
        else:
            final_result = "failed"

        # Notation pass: when the class has notationStrict=True, ask Claude
        # to flag any notation problem found in the steps WITHOUT flipping
        # the verdict. The returned value is a language-neutral key (one of
        # NOTATION_KEYS) — the iOS client maps it through Localizations.swift
        # to a localized banner. Skipped entirely when notationStrict is
        # false to save Anthropic credits.
        # Failed work: which skill failed at each wrong step, and how (for
        # the teacher's diagnosis), while the notation note finishes.
        diagnosis: list | None = (
            _diagnose_errors(client, statement, expected_answer, student_steps,
                             step_results, context.get("skill_ids") or [])
            if not all_correct else None
        )
        if diagnosis and missing and diagnosis[-1] is None:
            # The last line is right in itself: the gap is what it leaves out.
            exercise_skills = [s for s in context.get("skill_ids") or [] if taxonomy.is_skill(s)]
            diagnosis[-1] = {
                "skillID": exercise_skills[0] if exercise_skills else None,
                "errorType": "incomplete",
                "note": f"Réponse incomplète : il manque {', '.join(missing)}.",
            }
        error_tags: list | None = _error_tags(diagnosis) if diagnosis is not None else None
        notation_note_key: str | None = (
            notation_future.result() if notation_future is not None else None
        )

        # ISSUE-004: previously a persist failure was logged and swallowed,
        # so the teacher's inbox would never see a submission whose write
        # had failed. Now we retry a few times and then surface the failure
        # to the iOS client via HttpsError so it can prompt the student to
        # retry submission. The in-memory result is still returned on
        # success, so the student gets feedback on the happy path.
        persist_error = _persist_correction(
            submission_id=submission_id,
            step_results=step_results,
            first_error_index=first_error_index,
            final_result=final_result,
            notation_note_key=notation_note_key,
            error_tags=error_tags,
            diagnosis=diagnosis,
        )
        if persist_error is not None:
            raise https_fn.HttpsError(
                code=https_fn.FunctionsErrorCode.UNAVAILABLE,
                message=(
                    "La correction a réussi mais l'enregistrement a échoué. "
                    "Réessayez dans quelques instants."
                ),
                details={"reason": str(persist_error)},
            )

        response: dict = {
            "stepResults": step_results,
            "firstErrorIndex": first_error_index,
            "allCorrect": all_correct,
        }
        if notation_note_key is not None:
            response["notationNoteKey"] = notation_note_key
        if error_tags is not None:
            response["errorTags"] = error_tags
        if diagnosis is not None:
            response["diagnosis"] = diagnosis
        return response

    except https_fn.HttpsError:
        raise
    except anthropic.APIError as e:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message=f"Erreur API Anthropic: {str(e)}",
        )
    except Exception as e:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message=f"Erreur lors de la correction: {str(e)}",
        )
