"""API settings — where the runs live, plus CORS, from env / `.env`."""

from __future__ import annotations

from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

# This file is <root>/src/api/config.py; runs live in <root>/apps.
_DEFAULT_APPS_ROOT = Path(__file__).resolve().parent.parent.parent / "apps"


class Settings(BaseSettings):
    """Read-only API config. Env vars (or `.env`) override every default."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # Root that holds `<app_id>/<run_id>/output.yaml` + images.
    apps_root: Path = _DEFAULT_APPS_ROOT
    # No auth: the emulator hits this directly. `["*"]` keeps it open.
    cors_origins: list[str] = ["*"]


settings = Settings()
