"""Tests for _helpers: JSON extraction with LaTeX, drawing flattening."""

import io

from PIL import Image

import _helpers


def test_extract_json_keeps_latex_commands():
    text = r'{"steps": ["x \Rightarrow y", "\frac{1}{2}", "2 \times 3", "\sqrt{4}"], "confidence": 0.9}'
    result = _helpers.extract_json(text)
    assert result["steps"] == [r"x \Rightarrow y", r"\frac{1}{2}", r"2 \times 3", r"\sqrt{4}"]


def test_extract_json_still_reads_valid_escapes():
    assert _helpers.extract_json('{"a": "line\\nbreak", "b": "q\\"uote"}') == {"a": "line\nbreak", "b": 'q"uote'}


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
