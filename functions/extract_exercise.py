"""
extract_exercise.py
Cloud Function that extracts LaTeX content from a photographed/scanned exercise image.

Uses Claude Haiku 4.5 Vision to:
1. Analyze the exercise image
2. Extract the mathematical statement as LaTeX
3. Identify the expected answer

The function receives a Cloud Storage path, downloads the image,
sends it to Claude, and returns structured LaTeX content.
"""

import base64
import os

import anthropic
import firebase_admin
# Note: only `storage` is needed here. The previously-imported `credentials`
# was unused — Cloud Functions use Application Default Credentials.
from firebase_admin import storage
from firebase_functions import https_fn

# Initialize Firebase Admin SDK (uses default credentials in Cloud Functions)
if not firebase_admin._apps:
    firebase_admin.initialize_app()


# System prompt for exercise extraction
EXTRACTION_PROMPT = """Tu es un assistant spécialisé dans l'extraction d'exercices de mathématiques à partir d'images.

Analyse l'image fournie et extrais :
1. L'énoncé de l'exercice en LaTeX/texte mixte
2. La réponse attendue en LaTeX

Règles de formatage :
- Utilise $...$ pour les expressions mathématiques en ligne
- Utilise $$...$$ pour les équations en mode display
- Le texte explicatif reste en texte brut (pas de LaTeX)
- Les fractions s'écrivent \\frac{a}{b}
- Les racines carrées s'écrivent \\sqrt{x}
- Les puissances s'écrivent x^{n}
- Les indices s'écrivent x_{i}
- Les systèmes d'équations utilisent \\begin{cases} ... \\end{cases}

Réponds UNIQUEMENT avec un JSON valide, sans markdown ni backticks :
{
  "statement": "L'énoncé complet en LaTeX/texte mixte",
  "expectedAnswer": "La réponse attendue en LaTeX pur (sans délimiteurs $ ou $$)"
}

Si tu ne peux pas identifier de réponse attendue, mets une chaîne vide pour expectedAnswer.
Si l'image n'est pas un exercice de mathématiques, retourne un statement décrivant ce que tu vois
et une chaîne vide pour expectedAnswer.
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
    # Validate input
    storage_path = req.data.get("storagePath") if req.data else None
    if not storage_path:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="Le champ 'storagePath' est requis.",
        )

    # Get Anthropic API key from environment
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message="Clé API Anthropic non configurée.",
        )

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

        # Call Claude Haiku 4.5 Vision
        client = anthropic.Anthropic(api_key=api_key)

        message = client.messages.create(
            # Claude Haiku 4.5 — the previous "20241022" suffix corresponds
            # to Claude 3.5 Haiku and is rejected by the Anthropic API.
            model="claude-haiku-4-5-20251001",
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
                            "text": EXTRACTION_PROMPT,
                        },
                    ],
                }
            ],
        )

        # Parse response
        response_text = message.content[0].text.strip()

        # Try to parse JSON
        import json

        try:
            result = json.loads(response_text)
        except json.JSONDecodeError:
            # Try to extract JSON from the response if it's wrapped in markdown
            import re

            json_match = re.search(r"\{.*\}", response_text, re.DOTALL)
            if json_match:
                result = json.loads(json_match.group())
            else:
                raise https_fn.HttpsError(
                    code=https_fn.FunctionsErrorCode.INTERNAL,
                    message="Impossible de parser la réponse de l'IA.",
                )

        statement = result.get("statement", "")
        expected_answer = result.get("expectedAnswer", "")

        return {
            "statement": statement,
            "expectedAnswer": expected_answer,
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
