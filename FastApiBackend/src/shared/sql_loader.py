"""Utility for loading SQL files from disk."""

from functools import cache
from pathlib import Path


@cache
def _read_sql_file(path: Path) -> str:
    """The raw file read, cached forever per path — SQL files are static
    assets baked into the deploy, so a process never needs to re-read one
    (the uncached version did a synchronous disk read on the async event
    loop for EVERY query on every request). Cache the RAW text only —
    formatting with per-call variables happens outside the cache."""
    return path.read_text()


def load_sql(
    filepath: str | Path,
    variables: dict[str, str] | None = None,
) -> str:
    """Load a SQL file and optionally format it with variables.

    Variables are inserted using Python str.format_map(),
    so use {variable_name} placeholders in the SQL file for
    structural parts (e.g., WHERE clauses). Use :param_name
    for bind parameters passed to SQLAlchemy.

    The underlying file read is cached per path (SQL files are static);
    only the first call for a given file touches the disk.

    Args:
        filepath: Path to the .sql file.
        variables: Optional dict of variables to interpolate
            into the SQL template.

    Returns:
        The SQL string, optionally formatted.

    Raises:
        FileNotFoundError: If the SQL file does not exist.
    """
    sql = _read_sql_file(Path(filepath))
    if variables:
        sql = sql.format_map(variables)
    return sql
