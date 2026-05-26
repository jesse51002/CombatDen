"""Transcript-pass settings — the Apify API token, from env / `.env`.

Kept separate from the API and the YouTube batch config so the read-only API
never depends on an Apify token, and so this manual script can run on its own.
"""

from __future__ import annotations

from pydantic_settings import BaseSettings, SettingsConfigDict


class TranscriptSettings(BaseSettings):
    """Config for the transcript-fetch script. Env / `.env` supplies the token."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    apify_token: str  # required; no default — fail loudly if absent


def transcript_settings() -> TranscriptSettings:
    """Load settings on demand (not at import) so tests don't need the token."""
    return TranscriptSettings()
