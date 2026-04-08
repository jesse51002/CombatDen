"""Guard against updates to immutable columns.

Provides a validation function that raises if any requested
update columns are immutable, preventing accidental overwrites of
primary keys, trigger-protected fields, and auto-generated values.
"""


def validate_mutable_columns(
    immutable: frozenset[str],
    columns: set[str],
) -> None:
    """Raise if any columns are immutable.

    Args:
        immutable: The frozenset of immutable column names
            for the target table.
        columns: The set of column names requested for update.

    Raises:
        ValueError: If any requested columns are immutable.
    """
    violations = columns & immutable
    if violations:
        raise ValueError(f"Cannot update immutable columns: {', '.join(sorted(violations))}")
