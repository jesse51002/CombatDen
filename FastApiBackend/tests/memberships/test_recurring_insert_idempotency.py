"""Integration: the partial unique index dedups RECURRING start rows too.

Recurring rows used to carry a NULL ``idempotency_key`` on the grounds that
``trg_recurring_no_active_memberships`` already blocks a duplicate. It does —
sequentially. But it is a ``SELECT COUNT`` inside a ``BEFORE INSERT`` trigger,
which is not race-safe: two concurrent re-fires of one start (a kiosk
double-tap, or a client retry that overlaps the original) each take their
snapshot before the other commits, both count zero live memberships, both pass,
and both insert. Two rows means two Stripe subscription line items — a double
bill that the Stripe-side charge idempotency does NOT prevent, because the two
rows are two legitimately different desired-state lines.

``member_memberships_unfiltered.idempotency_key``'s partial unique index is the
only guard that serializes that race, so the start now stamps a key on recurring
rows as well.

Both tests below run against the real shared local Supabase DB (the
``member_memberships_unfiltered`` FKs need real member / plan / price rows) and
clean up through the ``created`` registry.
"""

from __future__ import annotations

import asyncio
from datetime import date
from uuid import UUID, uuid4

import pytest
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.memberships import SQL_DIR
from src.memberships.memberships_exceptions import MembershipStartReplayError
from src.memberships.service.memberships_base import MemberMembershipsBase
from src.shared.sql_loader import load_sql

START_DATE = date(2026, 1, 1)


def _row(
    member_id: UUID,
    gym_id: UUID,
    plan_id: UUID,
    price_id: UUID,
    idempotency_key: UUID,
) -> dict:
    """A pending recurring start row, shaped exactly as ``_crm_insert`` wants."""
    return {
        "member_id": member_id,
        "paid_by_member_id": member_id,
        "gym_id": gym_id,
        "plan_id": plan_id,
        "price_id": price_id,
        "start_date": START_DATE,
        # Recurring rows carry no end_date (trg_recurring_no_end_date).
        "end_date": None,
        "last_paid_date": START_DATE,
        "next_due_date": None,
        "stripe_item_id": None,
        "total_price": 5000,
        "quantity": 1,
        "idempotency_key": idempotency_key,
    }


async def _count_rows_with_key(db_pool, key: UUID) -> int:
    """How many membership rows carry this idempotency key."""
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT count(*) FROM member_memberships_unfiltered "
                "WHERE idempotency_key = CAST(:key AS UUID)"
            ),
            {"key": str(key)},
        )
        return int(result.scalar_one())


async def _delete_rows_with_key(db_pool, key: UUID) -> None:
    """Remove the rows this test inserted (they carry no Stripe object)."""
    async with db_pool.session() as session:
        await session.execute(
            text(
                "DELETE FROM member_memberships_unfiltered "
                "WHERE idempotency_key = CAST(:key AS UUID)"
            ),
            {"key": str(key)},
        )
        await session.commit()


async def test_recurring_row_with_a_used_key_is_dropped(
    created,
    db_pool,
    gym_id,
) -> None:
    """A second recurring insert reusing a key is dropped, not stacked.

    Two DIFFERENT recurring plans are used on purpose: every recurring trigger
    (no-active, no-overlap, chronological-start) is scoped to the SAME plan_id,
    so two plans route around all three and leave the partial unique INDEX as
    the only thing that can reject the second row — which is exactly what is
    under test. It is the index, not the trigger, that has to hold.
    """
    member = await created.member(gym_id)
    plan_a = await created.plan(gym_id, plan_type="recurring")
    plan_b = await created.plan(gym_id, plan_type="recurring")
    key = uuid4()
    base = MemberMembershipsBase(db_pool, None, None)  # type: ignore[arg-type]

    try:
        first = await base._crm_insert([
            _row(member.member_id, gym_id, plan_a.plan_id, plan_a.price_id, key),
        ])
        assert len(first) == 1

        # Same key, a row the recurring triggers happily accept.
        with pytest.raises(MembershipStartReplayError):
            await base._crm_insert([
                _row(
                    member.member_id,
                    gym_id,
                    plan_b.plan_id,
                    plan_b.price_id,
                    key,
                ),
            ])

        assert await _count_rows_with_key(db_pool, key) == 1
    finally:
        await _delete_rows_with_key(db_pool, key)


async def test_concurrent_recurring_refire_converges_to_one_row(
    created,
    db_pool,
    gym_id,
) -> None:
    """The double-tap race: two concurrent identical inserts leave ONE row.

    The interleaving is forced rather than hoped for, so the test is
    deterministic:

    1. Session A executes the insert and does NOT commit — the row exists,
       uncommitted, and holds its entry in the partial unique index.
    2. Session B runs the SAME insert (same member, same plan, same key). Its
       BEFORE INSERT trigger reads A's uncommitted row as absent, so
       ``trg_recurring_no_active_memberships`` PASSES — this is precisely the
       race the trigger cannot see. B then blocks on the unique index.
    3. A commits. B unblocks, ``ON CONFLICT DO NOTHING`` drops its row, and B's
       RETURNING comes back empty.

    Exactly one row survives. Before recurring rows were keyed, step 2's index
    entry did not exist and BOTH rows committed.
    """
    member = await created.member(gym_id)
    plan = await created.plan(gym_id, plan_type="recurring")
    key = uuid4()
    sql = load_sql(SQL_DIR / "member_memberships_insert.sql")
    params = _insert_params(
        _row(member.member_id, gym_id, plan.plan_id, plan.price_id, key),
    )

    try:
        async with db_pool.session() as session_a:
            first = await session_a.execute(text(sql), params)
            assert len(first.mappings().all()) == 1  # inserted, NOT committed

            async with db_pool.session() as session_b:
                task_b = asyncio.create_task(
                    session_b.execute(text(sql), params),
                )
                # Let B get past its trigger and block on the index. It cannot
                # see A's row yet, so the trigger cannot be what stops it.
                await asyncio.sleep(0.5)
                assert not task_b.done(), (
                    "session B should be BLOCKED on the unique index; if it "
                    "finished early the interleaving this test depends on did "
                    "not happen"
                )

                await session_a.commit()
                second = await task_b
                assert second.mappings().all() == []  # ON CONFLICT dropped it
                await session_b.commit()

        assert await _count_rows_with_key(db_pool, key) == 1
    finally:
        await _delete_rows_with_key(db_pool, key)


def _insert_params(row: dict) -> dict:
    """The array-shaped bind params ``member_memberships_insert.sql`` expects.

    Mirrors ``_crm_insert``'s own param build for a single row; the two tests
    that drive the raw SQL need it without the surrounding session handling.
    """
    return {
        "member_ids": [str(row["member_id"])],
        "paid_by_member_ids": [str(row["paid_by_member_id"])],
        "gym_ids": [str(row["gym_id"])],
        "plan_ids": [str(row["plan_id"])],
        "price_ids": [str(row["price_id"])],
        "start_dates": [row["start_date"]],
        "end_dates": [row["end_date"]],
        "last_paid_dates": [row["last_paid_date"]],
        "next_due_dates": [row["next_due_date"]],
        "stripe_item_ids": [row["stripe_item_id"]],
        "total_prices": [row["total_price"]],
        "quantities": [row["quantity"]],
        "sync_statuses": ["not_added"],
        "idempotency_keys": [str(row["idempotency_key"])],
    }
