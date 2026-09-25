"""
extract_exercise.py
Cloud Function that extracts LaTeX content from a photographed/scanned exercise image.

Uses Claude Vision (model set in claude_client.py) to:
1. Analyze the exercise image
2. Extract the mathematical statement as LaTeX
3. Identify the expected answer

The function receives a Cloud Storage path, downloads the image,
sends it to Claude, and returns structured LaTeX content.
"""

import base64
import json
import os

import anthropic
import firebase_admin
# Note: only `storage` is needed here. The previously-imported `credentials`
# was unused — Cloud Functions use Application Default Credentials.
from firebase_admin import storage
from firebase_functions import https_fn

import auth_guard
import claude_client
from _helpers import extract_json

# Initialize Firebase Admin SDK (uses default credentials in Cloud Functions)
if not firebase_admin._apps:
    firebase_admin.initialize_app()


# System prompt for exercise extraction. The prompt receives the teacher's
# competency catalog (a list of {id, label} pairs) and asks Claude to
# pick up to 5 IDs that best fit the exercise. If the catalog is empty
# or no competency fits, Claude returns an empty list.
EXTRACTION_PROMPT_TEMPLATE = """Tu es un assistant spécialisé dans l'extraction d'exercices de mathématiques à partir d'images.

Analyse l'image fournie et extrais :
1. L'énoncé de l'exercice en LaTeX/texte mixte
2. La réponse attendue en LaTeX
3. Les compétences pertinentes (jusqu'à 5) sélectionnées dans le catalogue de l'enseignant

Règles de formatage :
- Utilise $...$ pour les expressions mathématiques en ligne
- Utilise $$...$$ pour les équations en mode display
- Le texte explicatif reste en texte brut (pas de LaTeX)
- Les fractions s'écrivent \\frac{{a}}{{b}}
- Les racines carrées s'écrivent \\sqrt{{x}}
- Les puissances s'écrivent x^{{n}}
- Les indices s'écrivent x_{{i}}
- Les systèmes d'équations utilisent \\begin{{cases}} ... \\end{{cases}}

Catalogue de compétences disponible (n'utilise que ces IDs, pas de texte libre) :
{competencies}

Réponds UNIQUEMENT avec un JSON valide, sans markdown ni backticks :
{{
  "statement": "L'énoncé complet en LaTeX/texte mixte",
  "expectedAnswer": "La réponse attendue en LaTeX pur (sans délimiteurs $ ou $$)",
  "competencyIDs": ["id1", "id2"]
}}

Si tu ne peux pas identifier de réponse attendue, mets une chaîne vide pour expectedAnswer.
Si aucune compétence du catalogue ne convient, retourne un tableau vide pour competencyIDs.
Si l'image n'est pas un exercice de mathématiques, retourne un statement décrivant ce que tu vois,
une chaîne vide pour expectedAnswer, et un tableau vide pour competencyIDs.
"""


def extract_exercise_handler(req: https_fn.CallableRequest) -> dict:
    """Handle the extract_exercise Cloud Function call.

    Args:
        req: The callable request with data["storagePath"].

    Returns:
        dict with "statement" and "expectedAnswer".

    Raises:
        https_fn.HttpsError on validation or processing failures.
    """
    # Caller must be an authenticated teacher (email/password sign-in).
    # Students cannot import exercises, and unauthenticated callers cannot
    # ask the function to read arbitrary Storage paths (ISSUE-014).
    auth = getattr(req, "auth", None)
    if auth is None or not getattr(auth, "uid", None):
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.UNAUTHENTICATED,
            message="Connexion enseignant requise.",
        )

    # Validate input
    storage_path = req.data.get("storagePath") if req.data else None
    if not storage_path:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="Le champ 'storagePath' est requis.",
        )

    # Teachers only, and only exercise images: this must not become a way
    # to read students' drawings.
    auth_guard.require_teacher(req)
    if not auth_guard.is_safe_path(storage_path, "exercises/"):
        raise auth_guard._denied()

    # Optional teacher competency catalog: [{ "id": "abc", "label": "Équations du 1er degré" }, ...].
    # If absent or empty, the AI will not propose any tags.
    raw_competencies = req.data.get("competencies") if req.data else None
    competencies: list = raw_competencies if isinstance(raw_competencies, list) else []
    valid_competency_ids = set()
    competency_lines = []
    for entry in competencies:
        if not isinstance(entry, dict):
            continue
        cid = entry.get("id")
        label = entry.get("label")
        if not cid or not label:
            continue
        valid_competency_ids.add(cid)
        # Limit to 60 chars per label to keep the prompt compact.
        clean_label = str(label)[:60].replace("\n", " ")
        competency_lines.append(f"- {cid}: {clean_label}")
    if competency_lines:
        catalog_block = "\n".join(competency_lines[:80])  # cap to 80 entries
    else:
        catalog_block = "(catalogue vide — retourne competencyIDs: [])"

    # Claude client for the configured provider (Vertex AI in Europe by
    # default, see claude_client.py).
    client = claude_client.create_client()

    try:
        # Download image from Cloud Storage
        bucket = storage.bucket()
        blob = bucket.blob(storage_path)

        if not blob.exists():
            raise https_fn.HttpsError(
                code=https_fn.FunctionsErrorCode.NOT_FOUND,
                message=f"Image non trouvée: {storage_path}",
            )

        image_bytes = blob.download_as_bytes()
        image_base64 = base64.b64encode(image_bytes).decode("utf-8")

        # Determine media type from file extension
        ext = storage_path.rsplit(".", 1)[-1].lower() if "." in storage_path else "jpg"
        media_type_map = {
            "jpg": "image/jpeg",
            "jpeg": "image/jpeg",
            "png": "image/png",
            "gif": "image/gif",
            "webp": "image/webp",
        }
        media_type = media_type_map.get(ext, "image/jpeg")

        # Call Claude Vision
        message = client.messages.create(
            model=claude_client.model_id(),
            max_tokens=2048,
            messages=[
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "image",
                            "source": {
                                "type": "base64",
                                "media_type": media_type,
                                "data": image_base64,
                            },
                        },
                        {
                            "type": "text",
                            "text": EXTRACTION_PROMPT_TEMPLATE.format(
                                competencies=catalog_block
                            ),
                        },
                    ],
                }
            ],
        )

        # Parse response (markdown fences and trailing prose tolerated).
        try:
            result = extract_json(message.content[0].text)
        except json.JSONDecodeError:
            raise https_fn.HttpsError(
                code=https_fn.FunctionsErrorCode.INTERNAL,
                message="Impossible de parser la réponse de l'IA.",
            )

        statement = result.get("statement", "")
        expected_answer = result.get("expectedAnswer", "")
        # Filter Claude's suggested competency IDs to those that actually
        # exist in the supplied catalog — guards against hallucinations.
        raw_ids = result.get("competencyIDs", []) or []
        competency_ids: list = [
            cid for cid in raw_ids
            if isinstance(cid, str) and cid in valid_competency_ids
        ][:5]

        # Defence in depth (ISSUE-009): if Claude returned blank fields,
        # the source image was either empty or not a math exercise. Reject
        # rather than letting the editor populate empty fields.
        if not (statement or "").strip() and not (expected_answer or "").strip():
            raise https_fn.HttpsError(
                code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
                message="Aucun contenu détecté dans l'image.",
            )

        return {
            "statement": statement,
            "expectedAnswer": expected_answer,
            "competencyIDs": competency_ids,
        }

    except https_fn.HttpsError:
        raise
    except anthropic.APIError as e:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message=f"Erreur API Anthropic: {str(e)}",
        )
    except Exception as e:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message=f"Erreur lors de l'extraction: {str(e)}",
        )
