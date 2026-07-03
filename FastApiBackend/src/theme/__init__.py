"""Theme domain — gym showcase (branded class/reward cards)."""

from pathlib import Path

import src.shared.db_schema_path  # noqa: F401, E402

SQL_DIR = Path(__file__).resolve().parent / "sql"
SHOWCASE_DEFAULTS_FILE = (
    Path(__file__).resolve().parent
    / "showcase_defaults"
    / "theme_showcase_defaults.yaml"
)
