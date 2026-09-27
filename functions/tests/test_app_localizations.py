"""The app's FR → EN table is a Swift dictionary literal: a duplicate key
is a crash at the first translated string. Checked here since the Swift
compiler does not catch it."""

import collections
import pathlib
import re

SOURCE = pathlib.Path(__file__).resolve().parents[2] / "Core/Resources/Localizations.swift"


def test_no_duplicate_translation_keys():
    text = SOURCE.read_text(encoding="utf-8")
    body = text[text.index("static let fr2en"):]
    keys = re.findall(r'^\s*"((?:[^"\\]|\\.)*)"\s*:', body, flags=re.M)
    duplicates = [key for key, count in collections.Counter(keys).items() if count > 1]
    assert not duplicates, duplicates
