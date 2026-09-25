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
    # LaTeX inside JSON strings. Claude often writes single backslashes:
    # "\\sqrt" is an invalid escape (json.loads fails) and, worse, "\\times",
    # "\\frac", "\\beta" are *valid* escapes (tab, form feed, backspace +
    # letters) that silently corrupt the step ("2 \\times x" -> "2 <TAB>imes x").
    # Repair before the first parse, not only after a failure.
    s = _escape_stray_backslashes(s)
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


_VALID_ESCAPES = set('"\\/bfnrtu')

# LaTeX commands that begin with a letter JSON also uses as an escape
# (\\b \\f \\n \\r \\t). "\\times" must stay LaTeX, but "\\nDonner" is a real
# newline followed by a word, so match whole command names, not prefixes.
_LATEX_COMMANDS = {
    # b
    "beta", "bar", "binom", "bmod", "begin", "big", "Big", "bigg", "Bigg", "bigl", "bigr",
    "boldsymbol", "bot", "bullet", "backslash", "bf", "bigcup", "bigcap", "boxed",
    # f
    "frac", "forall", "flat", "frown", "footnotesize",
    # n
    "neq", "ne", "neg", "nabla", "notin", "not", "nu", "nleq", "ngeq", "nless", "ngtr",
    "nmid", "nparallel", "nsubseteq", "newline", "noindent", "nearrow", "nwarrow",
    # r
    "right", "rightarrow", "Rightarrow", "rho", "rangle", "rceil", "rfloor", "rm",
    "rbrace", "rvert", "Rvert", "rightleftharpoons", "rtimes",
    # t
    "times", "text", "textbf", "textit", "textrm", "tan", "tanh", "theta", "tau", "to",
    "top", "triangle", "tfrac", "tilde", "tiny", "therefore", "textstyle", "triangleq",
}


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
            if nxt in "bfnrt":
                j = i + 1
                while j < len(s) and s[j].isalpha():
                    j += 1
                if s[i + 1:j] in _LATEX_COMMANDS:
                    out.append("\\\\")  # LaTeX: keep the backslash literally
                else:
                    out.append(ch)  # JSON escape (\\n newline, \\t tab…)
                i += 1
                continue
            if nxt in _VALID_ESCAPES:
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
