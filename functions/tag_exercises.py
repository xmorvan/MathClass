"""
tag_exercises.py
Tags exercises with the skills of the taxonomy they practise, so the
teacher's statistics can diagnose by domain, competency and skill.

Called by the app after an exercise is created or edited (teacher only,
own exercises), and by tools/backfill_skills.py for existing exercises.
"""

from __future__ import annotations

import json

from firebase_functions import https_fn

import auth_guard
import claude_client
import taxonomy
from _helpers import extract_json

TAG_SYSTEM = """Tu classes des exercices de mathématiques dans un référentiel de savoir-faire.

Référentiel (identifiant — Domaine › Compétence › Savoir-faire) :
{catalog}

Pour l'exercice donné, choisis de 1 à 4 savoir-faire du référentiel : ceux que l'élève doit mobiliser pour le réussir, du plus central au plus secondaire. Sois précis : pour « Développer (x+1)(x−2)(x+3) », choisis le produit de trois facteurs, pas la simple distributivité. N'utilise que des identifiants du référentiel, recopiés exactement.

Réponds UNIQUEMENT en JSON : {{"skillIDs": ["id1", "id2"]}}"""


def _system_blocks() -> list:
    return [{
        "type": "text",
        "text": TAG_SYSTEM.format(catalog=taxonomy.catalog_text()),
        "cache_control": {"type": "ephemeral"},
    }]


def suggest_skills(client, statement: str, expected_answer: str) -> list:
    """Skill IDs for an exercise (best effort: [] on any failure)."""
    if not (statement or "").strip():
        return []
    try:
        message = client.messages.create(
            model=claude_client.model_id(),
            max_tokens=200,
            temperature=0,
            system=_system_blocks(),
            messages=[{
                "role": "user",
                "content": f"Énoncé : {statement}\nRéponse attendue : {expected_answer or '(non précisée)'}",
            }],
        )
        return taxonomy.valid_skills(extract_json(message.content[0].text).get("skillIDs"))
    except (json.JSONDecodeError, AttributeError, IndexError) as exc:
        print(f"[tag_exercises] unreadable answer: {exc}")
        return []
    except Exception as exc:  # noqa: BLE001 — tagging must never break a save
        print(f"[tag_exercises] tagging failed: {exc}")
        return []


def _get_firestore():
    from firebase_admin import firestore
    return firestore.client()


def tag_exercises_handler(req: https_fn.CallableRequest) -> dict:
    """Tags the caller's exercises. req.data: {exerciseIDs: [...] (≤ 20),
    force: bool (retag already tagged ones)}. Returns {exerciseID: [skillIDs]}."""
    teacher_uid = auth_guard.require_teacher(req)
    ids = (req.data or {}).get("exerciseIDs")
    if not isinstance(ids, list) or not ids or len(ids) > 20 or not all(isinstance(i, str) and i for i in ids):
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="'exerciseIDs' : de 1 à 20 identifiants.",
        )
    force = bool((req.data or {}).get("force"))
    db = _get_firestore()
    client = claude_client.create_client()
    tagged = {}
    for exercise_id in ids:
        reference = db.collection("exercises").document(exercise_id)
        snapshot = reference.get()
        if not snapshot.exists:
            continue
        data = snapshot.to_dict() or {}
        if data.get("teacherID") != teacher_uid:
            raise auth_guard._denied()
        if data.get("skillIDs") and not force:
            tagged[exercise_id] = data["skillIDs"]
            continue
        skill_ids = suggest_skills(client, data.get("statement", ""), data.get("expectedAnswer", ""))
        if skill_ids:
            reference.update({"skillIDs": skill_ids})
        tagged[exercise_id] = skill_ids
    return {"skillIDs": tagged}
