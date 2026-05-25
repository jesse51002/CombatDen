"""API settings — where the runs live, plus CORS, from env / `.env`."""

from __future__ import annotations

from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

# This file is <root>/src/api/config.py; runs live in <root>/apps.
_ROOT = Path(__file__).resolve().parent.parent.parent
_DEFAULT_APPS_ROOT = _ROOT / "apps"
# The global Lottie preset library. A lottie output references a preset by
# library-relative path (e.g. ``animations/confetti_burst.json``); the
# delivery endpoint resolves it against this root. Presets are shared across
# tenants, so they live here, not under a per-run dir.
_DEFAULT_LOTTIE_LIBRARY_ROOT = _ROOT / "assets" / "lottie_animations"


class Settings(BaseSettings):
    """Read-only API config. Env vars (or `.env`) override every default."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # Root that holds `<app_id>/<run_id>/output.yaml` + images.
    apps_root: Path = _DEFAULT_APPS_ROOT
    # Root of the global Lottie preset library the lottie endpoint serves
    # from (preset files are shared across tenants, not per-run).
    lottie_library_root: Path = _DEFAULT_LOTTIE_LIBRARY_ROOT
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
