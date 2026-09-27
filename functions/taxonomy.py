"""
taxonomy.py
The skill taxonomy (domaine > compétence > savoir-faire) shared with the
app: exercises are tagged with skill IDs and every wrong step of a copy is
tied to the skill that failed. Built from taxonomy_source.txt by
tools/build_taxonomy.py.
"""

from __future__ import annotations

import json
import pathlib
from functools import lru_cache

_PATH = pathlib.Path(__file__).resolve().parent / "taxonomy.json"

# How a step went wrong, independently of the skill.
ERROR_TYPES = (
    "sign_error",     # signe perdu ou inversé
    "arithmetic",     # erreur de calcul numérique
    "algebra",        # règle algébrique mal appliquée
    "method",         # mauvaise méthode ou étape sautée
    "conceptual",     # notion mal comprise
    "incomplete",     # réponse partielle (une solution sur deux, pas de conclusion)
    "notation",       # écriture incorrecte
    "misread",        # énoncé mal lu, mauvaises données
    "consequence",    # étape juste mais qui découle d'une erreur précédente
)


@lru_cache(maxsize=1)
def load() -> dict:
    return json.loads(_PATH.read_text(encoding="utf-8"))


@lru_cache(maxsize=1)
def skills() -> dict:
    """skill ID → (domain label, competency label, skill label), in French."""
    table = {}
    for domain in load()["domains"]:
        for competency in domain["competencies"]:
            for skill in competency["skills"]:
                table[skill["id"]] = (domain["fr"], competency["fr"], skill["fr"])
    return table


def is_skill(skill_id) -> bool:
    return isinstance(skill_id, str) and skill_id in skills()


@lru_cache(maxsize=1)
def catalog_text() -> str:
    """One line per skill, for prompts: `id — Domaine › Compétence › Savoir-faire`."""
    return "\n".join(
        f"{skill_id} — {domain} › {competency} › {skill}"
        for skill_id, (domain, competency, skill) in skills().items()
    )


def valid_skills(candidates, limit: int = 4) -> list:
    """Known skill IDs from a model answer, deduplicated, in order."""
    result = []
    for candidate in candidates or []:
        if is_skill(candidate) and candidate not in result:
            result.append(candidate)
    return result[:limit]
