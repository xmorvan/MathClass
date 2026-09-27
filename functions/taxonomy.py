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


# Skills practised inside another one: when an exercise targets the key,
# a mistake the model files under one of the values is a failure at the
# key ("expand (x+1)(x−2)(x+3)": a slip in a double distributivity is a
# failure at expanding three factors).
PART_OF = {
    "litteral.developper.trois-facteurs": {
        "litteral.developper.double-distributivite",
        "litteral.developper.simple-distributivite",
    },
    "litteral.developper.developper-reduire": {
        "litteral.developper.simple-distributivite",
        "litteral.developper.double-distributivite",
    },
}


def within_exercise(skill_id, exercise_skills) -> str | None:
    """The exercise skill a diagnosed skill is part of, else the skill."""
    for exercise_skill in exercise_skills or []:
        if skill_id in PART_OF.get(exercise_skill, ()):
            return exercise_skill
    return skill_id


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
