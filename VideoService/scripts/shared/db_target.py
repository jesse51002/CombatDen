"""Pick which database the write scripts (sync-gyms / import-yaml) target.

The read API always uses the local ``.env``. The write scripts instead honour an
``ENV_FILE`` environment flag so they can be pointed at a different config file —
e.g. ``ENV_FILE=.env.prod make sync-gyms GYM_ID=all`` writes to prod. Default is
``.env`` (the local DB), so prod is always an explicit opt-in.

Loading a separate ``Settings`` from the chosen file (rather than mutating the
global one) keeps the API's config untouched.
"""

from __future__ import annotations

import logging
import os

from sqlalchemy.engine import make_url

from src.shared.config import Settings
from src.shared.database import DirectDatabasePool

logger = logging.getLogger(__name__)

ENV_FILE_VAR = "ENV_FILE"
DEFAULT_ENV_FILE = ".env"


def build_write_pool() -> DirectDatabasePool:
    """Build a write pool against the DB in the ``ENV_FILE`` config (default
    ``.env``). Logs the resolved target host so it's obvious when prod is hit."""
    env_file = os.environ.get(ENV_FILE_VAR, DEFAULT_ENV_FILE)
    cfg = Settings(_env_file=env_file)  # type: ignore[call-arg]
    if not cfg.database_url:
        raise SystemExit(f"no DATABASE_URL found in {env_file!r}")
    host = make_url(cfg.database_url).host or "?"
    logger.warning("DB target: %s  (host: %s)", env_file, host)
    return DirectDatabasePool(database_url=cfg.database_url)
