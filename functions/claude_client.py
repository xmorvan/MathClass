"""
claude_client.py
One place to build the Claude client and pick the model.

Two providers, chosen with the CLAUDE_PROVIDER environment variable
(functions/.env):
  - "vertex" (default): Claude on Google Cloud Vertex AI, in a European
    region (CLAUDE_VERTEX_REGION, default europe-west1). Students' work
    stays in Europe and Google is the only processor, as for Firebase.
    Authenticates with the function's service account; no API key.
  - "anthropic": the Anthropic API directly (data processed and stored in
    the United States), with the ANTHROPIC_API_KEY secret.

CLAUDE_MODEL overrides the model ID, e.g. when Claude Haiku 4.5 is
retired (Google Cloud lists it as available until at least 2026-10-15).
"""

from __future__ import annotations

import os

import anthropic
from firebase_functions import https_fn

DEFAULT_MODELS = {
    # Vertex AI names this model without the date suffix.
    "vertex": "claude-haiku-4-5",
    "anthropic": "claude-haiku-4-5-20251001",
}


def provider() -> str:
    value = os.environ.get("CLAUDE_PROVIDER", "vertex").strip().lower()
    if value not in DEFAULT_MODELS:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message=f"CLAUDE_PROVIDER inconnu : {value!r}.",
        )
    return value


def model_id() -> str:
    return os.environ.get("CLAUDE_MODEL") or DEFAULT_MODELS[provider()]


def create_client():
    """Return a client exposing `messages.create` for the configured provider."""
    if provider() == "anthropic":
        api_key = os.environ.get("ANTHROPIC_API_KEY")
        if not api_key:
            raise https_fn.HttpsError(
                code=https_fn.FunctionsErrorCode.INTERNAL,
                message="Clé API Anthropic non configurée.",
            )
        return anthropic.Anthropic(api_key=api_key)

    project_id = (
        os.environ.get("CLAUDE_VERTEX_PROJECT")
        or os.environ.get("GOOGLE_CLOUD_PROJECT")
        or os.environ.get("GCLOUD_PROJECT")
    )
    if not project_id:
        raise https_fn.HttpsError(
            code=https_fn.FunctionsErrorCode.INTERNAL,
            message="Projet Google Cloud introuvable pour Vertex AI.",
        )
    region = os.environ.get("CLAUDE_VERTEX_REGION", "europe-west1")
    return anthropic.AnthropicVertex(project_id=project_id, region=region)
