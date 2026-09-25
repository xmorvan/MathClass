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

    # LaTeX inside JSON strings: "\\frac" is fine, but a single "\\Rightarrow"
    # or "\\sqrt" is an invalid escape and breaks json.loads. Double every
    # backslash that doesn't start a valid JSON escape, then retry.
    repaired = _escape_stray_backslashes(s)
    if repaired != s:
        try:
            return json.loads(repaired)
        except json.JSONDecodeError:
            pass
        s = repaired

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


_VALID_ESCAPES = set('"\\/bfnrtu')


def _escape_stray_backslashes(s: str) -> str:
    out = []
    i = 0
    while i < len(s):
        ch = s[i]
        if ch == "\\":
            nxt = s[i + 1] if i + 1 < len(s) else ""
            if nxt == "\\":
                out.append("\\\\")
                i += 2
                continue
            # \b, \f, \n, \r, \t followed by a letter are LaTeX commands
            # (\frac, \times, \beta…), not JSON control escapes.
            if nxt in _VALID_ESCAPES and not (nxt in "bfnrt" and i + 2 < len(s) and s[i + 2].isalpha()):
                out.append(ch)
            else:
                out.append("\\\\")
            i += 1
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def flatten_on_white(image_bytes: bytes) -> tuple[bytes, str]:
    """Composite a transparent drawing onto a white background.

    PencilKit exports black strokes on a transparent background; rendered
    on black, the handwriting disappears for the model. Returns PNG bytes
    and the media type; images without transparency are returned as-is.
    """
    import io

    from PIL import Image

    with Image.open(io.BytesIO(image_bytes)) as img:
        if img.mode not in ("RGBA", "LA", "P"):
            return image_bytes, "image/" + (img.format or "png").lower()
        rgba = img.convert("RGBA")
        background = Image.new("RGB", rgba.size, (255, 255, 255))
        background.paste(rgba, mask=rgba.getchannel("A"))
        out = io.BytesIO()
        background.save(out, format="PNG")
        return out.getvalue(), "image/png"


def make_anthropic_client(api_key: str) -> anthropic.Anthropic:
    """Anthropic client with a 20s request timeout and 2 retries.

    The 60–120s Cloud Functions wall clock is the hard ceiling. Without a
    timeout, a hung Anthropic request blocks the function until the wall
    clock fires and the user gets a 504 with no useful diagnostic.
    """
    return anthropic.Anthropic(api_key=api_key, timeout=20.0, max_retries=2)
