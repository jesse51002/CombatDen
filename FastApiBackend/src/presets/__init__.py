"""Presets domain — import a template_gym template into a real gym's prod tables."""

from pathlib import Path

# Register the Database schema package on sys.path before any submodule does a
# ``from schema.* import ...`` (mirrors src/videos/__init__.py).
import src.shared.db_schema_path  # noqa: F401, E402

SQL_DIR = Path(__file__).resolve().parent / "sql"
