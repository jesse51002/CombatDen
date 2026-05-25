"""Settings for the LLM-backed classification pass — provider keys + retry
bound, from env / `.env`.

Kept separate from ``src/api/config.py`` so the read-only API never depends on
an LLM key. Mirrors ``CustomizationService/src/core/config.py`` but the provider
keys default to ``""`` rather than being required: this service only routes
Gemma via ``gemini``, and importing the client (e.g. in tests with a stubbed
``LLMClient``) must not fail just because a key is absent — a real call without
a key fails loudly at request time via ``provider_keys``.
"""

from __future__ import annotations

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Classification config. Env vars (or `.env`) override every default."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # litellm routes each call by the provider prefix on that call's model id;
    # the model id lives in the module that makes the call (a per-call
    # constant), never here. These are the keys litellm uses per provider.
    # Gemma (``gemini/gemma-...``) routes on the gemini key.
    anthropic_api_key: str = ""
    gemini_api_key: str = ""
    openai_api_key: str = ""


settings = Settings()
