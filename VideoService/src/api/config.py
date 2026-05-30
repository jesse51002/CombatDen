"""API settings — the single-tenant data root (holds `gyms/`, `videos/`,
`cost_log.yaml`), plus CORS, from env / `.env`."""

from __future__ import annotations

from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

# This file is <root>/src/api/config.py; the data lives flat under <root>.
_DEFAULT_DATA_ROOT = Path(__file__).resolve().parent.parent.parent


class Settings(BaseSettings):
    """Read-only API config. Env vars (or `.env`) override every default."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # Single-tenant data root holding `gyms/`, `videos/`, `cost_log.yaml`.
    data_root: Path = _DEFAULT_DATA_ROOT
    # No auth: the demo hits this directly. `["*"]` keeps it open.
    cors_origins: list[str] = ["*"]


settings = Settings()
