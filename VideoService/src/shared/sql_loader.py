"""Utility for loading SQL files from disk.

Copied from ``FastApiBackend/src/shared/sql_loader.py`` — VideoService is
standalone, so it keeps its own copy rather than importing across services. Every
query lives in its own ``.sql`` file and is read at use (the "no inline SQL" rule).
"""

from pathlib import Path


def load_sql(
    filepath: str | Path,
    variables: dict[str, str] | None = None,
) -> str:
    """Load a SQL file and optionally format it with variables.

    Variables are inserted using Python ``str.format_map()``, so use
    ``{variable_name}`` placeholders in the SQL file for structural parts (e.g.
    WHERE clauses). Use ``:param_name`` for bind parameters passed to SQLAlchemy.

    Args:
        filepath: Path to the .sql file.
        variables: Optional dict of variables to interpolate into the template.

    Returns:
        The SQL string, optionally formatted.

    Raises:
        FileNotFoundError: If the SQL file does not exist.
    """
    path = Path(filepath)
    sql = path.read_text()
    if variables:
        sql = sql.format_map(variables)
    return sql
