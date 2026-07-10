"""Shared settings — the DB connection, the resource lock, and the data root.

The background worker (`src/worker`) and the gym-config sync scripts
(`scripts/`) are the only surviving consumers of this service now that the
read-only API has been retired. Both need a live connection to the shared
Supabase Postgres (`database_url`), the pool tuning knobs, the default lock
TTL for `ResourceLock`, and the authored-YAML `data_root` the sync/import
scripts read `gyms/` (and the legacy `videos/` / `cost_log.yaml`) from.
"""

from __future__ import annotations

from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

# This file is <root>/src/shared/config.py; the YAML data lives flat under <root>.
_DEFAULT_DATA_ROOT = Path(__file__).resolve().parent.parent.parent


class Settings(BaseSettings):
    """Shared DB + lock + data-root config. Env vars (or `.env`) override every default."""

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


settings = Settings()
