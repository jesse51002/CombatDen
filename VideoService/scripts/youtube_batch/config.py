"""Batch-script settings — the YouTube Data API key, from env / `.env`.

Kept separate from ``src/api/config.py`` so the read-only API never depends on a
YouTube key, and so this manual script can run without booting the API.
"""

from __future__ import annotations

from pydantic_settings import BaseSettings, SettingsConfigDict


class BatchSettings(BaseSettings):
    """Config for the YouTube batch script. Env / `.env` supplies the key."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    youtube_api_key: str  # required; no default — fail loudly if absent


def batch_settings() -> BatchSettings:
    """Load settings on demand (not at import) so tests don't need the key."""
    return BatchSettings()
