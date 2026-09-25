"""Tests for claude_client.py (provider and model selection)."""

from __future__ import annotations

import sys

import anthropic
import pytest

import claude_client

https_fn = sys.modules["firebase_functions"].https_fn


def test_vertex_is_the_default_provider(monkeypatch):
    monkeypatch.delenv("CLAUDE_PROVIDER", raising=False)
    assert claude_client.provider() == "vertex"
    assert claude_client.model_id() == "claude-haiku-4-5"


def test_vertex_client_uses_project_and_european_region(monkeypatch):
    monkeypatch.setenv("CLAUDE_PROVIDER", "vertex")
    monkeypatch.delenv("CLAUDE_VERTEX_PROJECT", raising=False)
    monkeypatch.delenv("CLAUDE_VERTEX_REGION", raising=False)
    monkeypatch.setenv("GCLOUD_PROJECT", "mathclass-test")
    captured = {}
    monkeypatch.setattr(
        anthropic, "AnthropicVertex", lambda **kwargs: captured.update(kwargs) or "vertex-client"
    )

    assert claude_client.create_client() == "vertex-client"
    assert captured == {"project_id": "mathclass-test", "region": "europe-west1"}


def test_vertex_without_project_fails_clearly(monkeypatch):
    monkeypatch.setenv("CLAUDE_PROVIDER", "vertex")
    for name in ("CLAUDE_VERTEX_PROJECT", "GOOGLE_CLOUD_PROJECT", "GCLOUD_PROJECT"):
        monkeypatch.delenv(name, raising=False)
    with pytest.raises(https_fn.HttpsError):
        claude_client.create_client()


def test_anthropic_provider_requires_api_key(monkeypatch):
    monkeypatch.setenv("CLAUDE_PROVIDER", "anthropic")
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    with pytest.raises(https_fn.HttpsError):
        claude_client.create_client()


def test_anthropic_provider_uses_dated_model_id(monkeypatch):
    monkeypatch.setenv("CLAUDE_PROVIDER", "anthropic")
    assert claude_client.model_id() == "claude-haiku-4-5-20251001"


def test_model_override(monkeypatch):
    monkeypatch.setenv("CLAUDE_MODEL", "claude-sonnet-5")
    assert claude_client.model_id() == "claude-sonnet-5"


def test_unknown_provider_rejected(monkeypatch):
    monkeypatch.setenv("CLAUDE_PROVIDER", "openai")
    with pytest.raises(https_fn.HttpsError):
        claude_client.provider()
