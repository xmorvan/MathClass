"""
recognize_handwriting.py
Cloud Function that recognizes student handwriting from a PencilKit PNG export.

Uses Claude Haiku 4.5 Vision to:
1. Analyze the handwritten math work
2. Identify each step of the student's reasoning
3. Convert each step into LaTeX
4. Return structured LaTeX steps with a confidence score

Accepts either a Cloud Storage path or a base64-encoded image directly.
"""

import base64
import json
import os
import re

import anthropic
import firebase_admin
from firebase_admin import storage
from firebase_functions import https_fn

import auth_guard

# Initialize Firebase Admin SDK (uses default credentials in Cloud Functions)
if not firebase_admin._apps:
    firebase_admin.initialize_app()


# System prompt for handwriting recognition
RECOGNITION_PROMPT = """Tu es un assistant spécialisé dans la reconnaissance d'écriture manuscrite mathématique d'élèves.

Analyse l'image fournie qui contient le travail manuscrit d'un élève sur un exercice de mathématiques.

Ta tâche :
1. Identifie chaque étape distincte du raisonnement de l'élève (chaque ligne ou groupe d'expressions)
2. Convertis chaque étape en LaTeX pur
3. Évalue ta confiance dans la reconnaissance (0.0 à 1.0)

Règles de formatage LaTeX :
- Chaque étape est une expression LaTeX pure (sans délimiteurs $ ou $$)
- Les fractions : \\frac{a}{b}
- Les racines carrées : \\sqrt{x}
- Les puissances : x^{n}
- Les indices : x_{i}
- Les égalités : =
- Les systèmes : \\begin{cases} ... \\end{cases}
- Les flèches d'implication : \\Rightarrow
- Multiplie : \\times (pas x)
- Division : \\div ou \\frac{}{}

Règles de reconnaissance :
- Lis de haut en bas, chaque ligne significative = une étape
- Ignore les ratures et gribouillages
- Si une expression est ambiguë, choisis l'interprétation la plus mathématiquement probable
- Les "=" consécutifs sur une même ligne font partie de la même étape
- Les résultats entourés ou soulignés sont la dernière étape

Réponds UNIQUEMENT avec un JSON valide, sans markdown ni backticks :
{
  "steps": ["étape 1 en LaTeX", "étape 2 en LaTeX", ...],
  "confidence": 0.95
}

Si l'image est vide, illisible, ou ne contient pas de mathématiques :
{
  "steps": [],
  "confidence": 0.0
}
"""


def recognize_handwriting_handler(req: https_fn.CallableRequest) -> dict:
    """Handle the recognize_handwriting Cloud Function call.

    Accepts either:
      - data["storagePath"]: Cloud Storage path to the PNG
      - data["imageBase64"]: Base64-encoded PNG image

    Returns:
        dict with "steps" (list of LaTeX strings) and "confidence" (float 0-1).

    Raises:
        https_fn.HttpsError on validation or processing failures.
    """
    if not req.data:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="Aucune donnée fournie.",
        )

    storage_path = req.data.get("storagePath")
    image_base64 = req.data.get("imageBase64")
    image_format = req.data.get("format", "png")

    if not storage_path and not image_base64:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INVALID_ARGUMENT,
            message="'storagePath' ou 'imageBase64' est requis.",
        )

    # Only the student who uploaded a drawing may have it read back.
    identity = auth_guard.require_student(req)
    if storage_path and not auth_guard.is_safe_path(
        storage_path, auth_guard.student_storage_prefix(identity)
    ):
        raise auth_guard._denied()

    # Get Anthropic API key
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message="Clé API Anthropic non configurée.",
        )

    try:
        # Get image data
        if storage_path:
            bucket = storage.bucket()
            blob = bucket.blob(storage_path)

            if not blob.exists():
                raise https_fn.HttpsError(
                    code=https_fn.FunctionsErrorCode.NOT_FOUND,
                    message=f"Image non trouvée: {storage_path}",
                )

            image_bytes = blob.download_as_bytes()
            image_b64 = base64.b64encode(image_bytes).decode("utf-8")

            # Determine media type from extension
            ext = storage_path.rsplit(".", 1)[-1].lower() if "." in storage_path else "png"
        else:
            image_b64 = image_base64
            ext = image_format.lower()

        media_type_map = {
            "jpg": "image/jpeg",
            "jpeg": "image/jpeg",
            "png": "image/png",
            "gif": "image/gif",
            "webp": "image/webp",
        }
        media_type = media_type_map.get(ext, "image/png")

        # Call Claude Haiku 4.5 Vision
        client = anthropic.Anthropic(api_key=api_key)

        message = client.messages.create(
            # Claude Haiku 4.5 — see extract_exercise.py for the rationale
            # on the date suffix.
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
                                "data": image_b64,
                            },
                        },
                        {
                            "type": "text",
                            "text": RECOGNITION_PROMPT,
                        },
                    ],
                }
            ],
        )

        # Parse response
        response_text = message.content[0].text.strip()

        try:
            result = json.loads(response_text)
        except json.JSONDecodeError:
            # Try to extract JSON from markdown-wrapped response
            json_match = re.search(r"\{.*\}", response_text, re.DOTALL)
            if json_match:
                result = json.loads(json_match.group())
            else:
                raise https_fn.HttpsError(
                    code=https_fn.FunctionsErrorCode.INTERNAL,
                    message="Impossible de parser la réponse de reconnaissance.",
                )

        steps = result.get("steps", [])
        confidence = result.get("confidence", 0.0)

        # Validate steps are all strings
        if not isinstance(steps, list):
            steps = []
        steps = [str(s) for s in steps if s]

        # Clamp confidence to [0, 1]
        confidence = max(0.0, min(1.0, float(confidence)))

        return {
            "steps": steps,
            "confidence": confidence,
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
            message=f"Erreur lors de la reconnaissance: {str(e)}",
        )
