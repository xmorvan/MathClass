"""
fake_claude.py
Canned Claude answers so the whole app can be clicked through against the
Firebase emulators without Vertex AI or an API key. Only reachable with
CLAUDE_PROVIDER=fake inside the Functions emulator (see claude_client.py).

Each call is recognised from its prompt and answered with valid JSON in
the shape the real prompt asks for.
"""

from __future__ import annotations

import json
import re
from types import SimpleNamespace


def _text_of(kwargs) -> str:
    parts = []
    for block in kwargs.get("system") or []:
        if isinstance(block, dict):
            parts.append(block.get("text", ""))
    for message in kwargs.get("messages") or []:
        content = message.get("content")
        if isinstance(content, str):
            parts.append(content)
        else:
            for block in content or []:
                if isinstance(block, dict) and block.get("type") == "text":
                    parts.append(block.get("text", ""))
    return "\n".join(parts)


def _has_image(kwargs) -> bool:
    for message in kwargs.get("messages") or []:
        content = message.get("content")
        if isinstance(content, list) and any(
            isinstance(b, dict) and b.get("type") == "image" for b in content
        ):
            return True
    return False


def _answer(kwargs) -> dict:
    text = _text_of(kwargs)
    if _has_image(kwargs):
        if "expectedAnswer" in text:
            return {
                "statement": "Résoudre $3x + 2 = 11$",
                "expectedAnswer": "x = 3",
                "competencyIDs": [],
            }
        return {"steps": ["2x = 8", "x = 4"], "confidence": 0.95}
    if '"pairs"' in text:
        steps = re.findall(r"^Étape \d+: (.*)$", text, flags=re.M)
        return {
            "pairs": [
                {"studentExpr": s, "referenceExpr": s, "description": "Étape"}
                for s in steps
            ]
        }
    if '"key"' in text:
        return {"key": None}
    if '"tags"' in text:
        return {"tags": []}
    if '"equivalent"' in text:
        return {"equivalent": True}
    return {}


class _Messages:
    def create(self, **kwargs):
        body = json.dumps(_answer(kwargs), ensure_ascii=False)
        return SimpleNamespace(content=[SimpleNamespace(text=body)])


class FakeClaude:
    def __init__(self) -> None:
        self.messages = _Messages()
