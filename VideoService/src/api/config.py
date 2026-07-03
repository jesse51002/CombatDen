"""API settings.

The read API now queries the shared Supabase Postgres (``database_url``) instead
of reading flat YAML, so a live DB connection is required at serve time. The
``data_root`` (holding the git-tracked ``gyms/`` + the legacy ``videos/`` /
``cost_log.yaml``) is still used by the ``sync-gyms`` and one-time import scripts
to read the authored YAML; the read path no longer touches it.
"""

from __future__ import annotations

from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

# This file is <root>/src/api/config.py; the YAML data lives flat under <root>.
_DEFAULT_DATA_ROOT = Path(__file__).resolve().parent.parent.parent


class Settings(BaseSettings):
    """Read-only API config. Env vars (or `.env`) override every default."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # Shared Supabase Postgres — postgresql+asyncpg://user:pass@host:5432/db.
    # Empty default so importing this module (e.g. in unit tests using a fake
    # store) never connects; the pool is built lazily and only then needs a URL.
    # Which env file populates this is selectable: the write scripts honour
    # ENV_FILE (e.g. ENV_FILE=.env.prod) so they can target prod; see
    # scripts/shared/db_target.py.
    database_url: str = ""
    db_pool_size: int = 10
    db_max_overflow: int = 10
    db_echo: bool = False

    # Default TTL (seconds) for a ResourceLock lease when a caller passes none;
    # a crashed/stuck holder self-heals once its lease expires. Mirrors the
    # FastApiBackend default. A long-running worker acquires with a short TTL
    # and heartbeats via ResourceLock.renew. See src/shared/services/resource_lock.py.
    lock_ttl_seconds: int = 60

    # Authored-YAML root for the sync-gyms / import scripts (holds `gyms/`, and
    # the legacy `videos/` + `cost_log.yaml` consumed once at cutover).
    data_root: Path = _DEFAULT_DATA_ROOT
    # No auth: the demo hits this directly. `["*"]` keeps it open.
    cors_origins: list[str] = ["*"]

    # CDN base for ThemeService assets. Defaults to the prod CDN so the derived
    # gym `celebration_image_url` ALWAYS points at the CDN (matching ThemeService,
    # whose images are de-baked) without depending on an App Runner env var being
    # set. Set this empty to emit the ThemeService-relative path the client
    # absolutises (local dev).
    assets_cdn_base_url: str = "https://cdn.combatden.net"


settings = Settings()
