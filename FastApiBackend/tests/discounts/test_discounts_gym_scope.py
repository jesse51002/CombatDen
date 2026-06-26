"""Regression test for C-035: cross-gym IDOR in discount update.

`DiscountsBase._get_discount` must scope the lookup to the requester's own
gym, so an employee of gym A can never read/mutate gym B's discount. These
are pure unit tests: the DB pool/session is mocked, no live DB or network.
"""

from __future__ import annotations

from contextlib import asynccontextmanager
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest

from src.discounts import SQL_DIR
from src.discounts.service.discounts_base import DiscountsBase


def _make_pool(row: dict | None) -> tuple[MagicMock, dict]:
    """Build a mock DB pool whose session returns `row`, capturing params."""
    captured: dict = {}

    result = MagicMock()
    mappings = MagicMock()
    mappings.fetchone.return_value = row
    result.mappings.return_value = mappings

    session = MagicMock()

    async def _execute(_sql: object, params: dict) -> MagicMock:
        captured.update(params)
        return result

    session.execute = AsyncMock(side_effect=_execute)

    @asynccontextmanager
    async def _session():
        yield session

    pool = MagicMock()
    pool.session = _session
    return pool, captured


def test_sql_filters_on_gym_id() -> None:
    """The lookup SQL must constrain the row to its owning gym."""
    sql = Path(SQL_DIR / "discounts_get_by_id.sql").read_text()
    assert "gym_id = :gym_id" in sql


@pytest.mark.asyncio
async def test_get_discount_binds_gym_id() -> None:
    """`_get_discount` threads gym_id into the bind params."""
    discount_id = uuid4()
    gym_id = uuid4()
    pool, captured = _make_pool({"discount_id": str(discount_id)})

    base = DiscountsBase(pool)
    await base._get_discount(discount_id, gym_id)

    assert captured["gym_id"] == str(gym_id)
    assert captured["discount_id"] == str(discount_id)


@pytest.mark.asyncio
async def test_cross_gym_lookup_raises_not_found() -> None:
    """A discount owned by another gym surfaces as not-found (-> 404)."""
    discount_id = uuid4()
    other_gym_id = uuid4()
    # gym filter excludes the row -> fetchone returns None.
    pool, _ = _make_pool(None)

    base = DiscountsBase(pool)
    with pytest.raises(ValueError, match="not found"):
        await base._get_discount(discount_id, other_gym_id)
