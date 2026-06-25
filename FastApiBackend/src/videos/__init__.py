"""Videos domain package."""

from pathlib import Path

# Register the Database schema package on sys.path before any submodule does a
# ``from schema.* import ...`` (this domain reuses the shared ``VideoGenre``).
import src.shared.db_schema_path  # noqa: F401, E402

SQL_DIR = Path(__file__).resolve().parent / "sql"
