"""Tests for _helpers: JSON extraction with LaTeX, drawing flattening."""

import io

from PIL import Image

import _helpers


def test_extract_json_keeps_latex_commands():
    text = r'{"steps": ["x \Rightarrow y", "\frac{1}{2}", "2 \times 3", "\sqrt{4}"], "confidence": 0.9}'
    result = _helpers.extract_json(text)
    assert result["steps"] == [r"x \Rightarrow y", r"\frac{1}{2}", r"2 \times 3", r"\sqrt{4}"]


def test_extract_json_still_reads_valid_escapes():
    # A JSON escape followed by a non-letter keeps its JSON meaning; followed
    # by a letter it is read as LaTeX (\\neq, \\ne, \\notin are common).
    assert _helpers.extract_json('{"a": "line\\n2", "b": "q\\"uote"}') == {"a": "line\n2", "b": 'q"uote'}
    assert _helpers.extract_json('{"a": "x \\neq 2"}') == {"a": "x \\neq 2"}


def test_flatten_on_white_removes_transparency():
    img = Image.new("RGBA", (4, 4), (0, 0, 0, 0))
    img.putpixel((1, 1), (0, 0, 0, 255))
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    flat, media_type = _helpers.flatten_on_white(buf.getvalue())
    out = Image.open(io.BytesIO(flat))
    assert media_type == "image/png"
    assert out.mode == "RGB"
    assert out.getpixel((0, 0)) == (255, 255, 255)
    assert out.getpixel((1, 1)) == (0, 0, 0)


def test_extract_json_does_not_turn_times_into_a_tab():
    # "\t" is a valid JSON escape: without the repair this parses to TAB+"imes".
    result = _helpers.extract_json('{"steps": ["2 \\times x = 10"], "confidence": 0.9}')
    assert result["steps"] == ["2 \\times x = 10"]
    assert "\t" not in result["steps"][0]


def test_extract_json_keeps_real_newlines_before_words():
    # Regression: "\\nDonner" is a newline + "Donner", not a LaTeX command.
    result = _helpers.extract_json('{"statement": "Résoudre $4x = 8$\\nDonner la valeur de $x$."}')
    assert result["statement"] == "Résoudre $4x = 8$\nDonner la valeur de $x$."
