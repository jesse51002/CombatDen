"""API settings — where the runs live, plus CORS, from env / `.env`."""

from __future__ import annotations

from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

# This file is <root>/src/api/config.py; runs live in <root>/apps.
_ROOT = Path(__file__).resolve().parent.parent.parent
_DEFAULT_APPS_ROOT = _ROOT / "apps"


class Settings(BaseSettings):
    """Read-only API config. Env vars (or `.env`) override every default."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # Root that holds `<app_id>/<run_id>/output.yaml` + images. Lottie slots
    # are served as baked per-run files from here too (``<run>/lotties/``), so
    # there is no separate library root on the delivery side.
    apps_root: Path = _DEFAULT_APPS_ROOT
    # No auth: the emulator hits this directly. `["*"]` keeps it open.
    cors_origins: list[str] = ["*"]

    # Google Fonts Developer API. The font delivery endpoint resolves the
    # per-variant TTF URLs by hitting Google's catalog, so the API process
    # needs the key too. Required — fail loud if absent, matching how the
    # pipeline process treats every provider key.
    google_fonts_api_key: str
    google_fonts_api_url: str = "https://www.googleapis.com/webfonts/v1/webfonts"
    google_fonts_request_timeout_seconds: float = 30.0
    google_fonts_ttl_seconds: int = 24 * 60 * 60


settings = Settings()
