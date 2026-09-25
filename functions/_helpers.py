"""
Shared helpers for the MathClass Cloud Functions.

Two utilities live here:

- `extract_json` — robust extraction of a JSON object from a Claude response,
  replacing the previous greedy `re.search(r"\\{.*\\}", ...)` pattern that
  failed on responses with nested JSON or markdown fences.

- `make_anthropic_client` — constructs an `anthropic.Anthropic` with a
  bounded request timeout and small retry budget. The Cloud Functions wall
  clock is 60–120s; without a client-side timeout an upstream Anthropic
  hang would consume the full budget.
"""

from __future__ import annotations

import json

import anthropic


def extract_json(text: str) -> dict:
    """Parse a JSON object out of a Claude text response.

    Tries `json.loads` first; if the model wrapped the output in markdown
    fences or trailing prose, strips fences then walks the brace stack
    starting at the first `{`. Raises `json.JSONDecodeError` if no balanced
    object can be found.
    """
    s = text.strip()
    # Strip common markdown fences.
    if s.startswith("```"):
        # Drop the opening fence (with or without language tag) and the
        # trailing fence if present.
        nl = s.find("\n")
        if nl != -1:
            s = s[nl + 1:]
        if s.endswith("```"):
            s = s[:-3]
        s = s.strip()
    try:
        return json.loads(s)
    except json.JSONDecodeError:
        pass

    start = s.find("{")
    if start < 0:
        raise json.JSONDecodeError("no JSON object found", s, 0)
    depth = 0
    in_string = False
    escape = False
    for i in range(start, len(s)):
        ch = s[i]
        if escape:
            escape = False
            continue
        if ch == "\\":
            escape = True
            continue
        if ch == '"':
            in_string = not in_string
            continue
        if in_string:
            continue
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return json.loads(s[start:i + 1])
    raise json.JSONDecodeError("unbalanced JSON object", s, start)


def make_anthropic_client(api_key: str) -> anthropic.Anthropic:
    """Anthropic client with a 20s request timeout and 2 retries.

    The 60–120s Cloud Functions wall clock is the hard ceiling. Without a
    timeout, a hung Anthropic request blocks the function until the wall
    clock fires and the user gets a 504 with no useful diagnostic.
    """
    return anthropic.Anthropic(api_key=api_key, timeout=20.0, max_retries=2)
