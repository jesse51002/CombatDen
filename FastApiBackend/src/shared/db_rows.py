"""Shared row-read primitive: execute -> ``.mappings()`` -> dict coercion.

Before this module, roughly a dozen services each hand-rolled their own
private ``_read_all`` / ``_fetchall`` / ``_read_one`` / ``_fetchone``
around ``session.execute(text(sql), params)`` -> ``.mappings()`` ->
``dict(row)``. The shape never varied, only the name — so one shared
implementation replaces every copy instead of letting the same three lines
drift service by service. A caller supplies an already-open
``AsyncSession`` and pre-loaded SQL text (via ``src.shared.sql_loader
.load_sql``); this module owns none of the session lifecycle or SQL
loading, only the read-and-coerce step.
"""

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession


async def fetch_all(
    session: AsyncSession,
    sql: str,
    params: dict | None = None,
) -> list[dict]:
    """Run ``sql`` on the caller's open ``session``; every row as a dict."""
    rows = (await session.execute(text(sql), params)).mappings().all()
    return [dict(row) for row in rows]


async def fetch_one(
    session: AsyncSession,
    sql: str,
    params: dict | None = None,
) -> dict | None:
    """Run ``sql`` on the caller's open ``session``; the first row as a
    dict, or ``None`` when there isn't one."""
    row = (await session.execute(text(sql), params)).mappings().fetchone()
    return dict(row) if row else None
