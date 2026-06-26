"""End-to-end: the on-demand invoice fetch lands the bill WITHOUT a webhook.

Proves the user's ask — "the background job correctly gets the invoice after a
thing". We charge a card (a REAL Stripe invoice is cut), then drive
``fetch_for_payer`` directly (the autouse fixture keeps the facade from
auto-firing it, and NO webhook is delivered in tests), and assert the
``member_invoices`` + ``member_invoice_line_items`` + ``member_charges`` rows now
exist. A second run is idempotent (no duplicate rows).
"""

import time
from unittest.mock import Mock
from uuid import uuid4

import pytest
from sqlalchemy import text

from src.core.config import settings
from src.memberships.memberships_schema import (
    MemberMembershipsChargeCardRequest,
)
from tests.helpers.cleanup import delete_member_data
from tests.helpers.service_factory import build_invoice_fetch


@pytest.fixture(autouse=True)
def _fast_retries(monkeypatch):
    """Don't really sleep between fetch attempts (the invoice is paid the
    instant charge_card returns, so a couple of immediate attempts suffice)."""
    monkeypatch.setattr(
        settings, "invoice_fetch_retry_delays_seconds", [0, 0, 0]
    )


async def _invoice_count(db_pool, member_id) -> int:
    async with db_pool.session() as session:
        res = await session.execute(
            text(
                "SELECT COUNT(*) AS n FROM member_invoices "
                "WHERE paid_by_member_id = :id AND status = 'paid'"
            ),
            {"id": str(member_id)},
        )
        return int(res.mappings().fetchone()["n"])


async def _charge_count(db_pool, member_id) -> int:
    async with db_pool.session() as session:
        res = await session.execute(
            text(
                "SELECT COUNT(*) AS n FROM member_charges c "
                "JOIN member_invoices i ON i.invoice_id = c.invoice_id "
                "WHERE i.paid_by_member_id = :id AND c.kind = 'payment'"
            ),
            {"id": str(member_id)},
        )
        return int(res.mappings().fetchone()["n"])


async def _line_item_count(db_pool, member_id) -> int:
    async with db_pool.session() as session:
        res = await session.execute(
            text(
                "SELECT COUNT(*) AS n FROM member_invoice_line_items li "
                "JOIN member_invoices i ON i.invoice_id = li.invoice_id "
                "WHERE i.paid_by_member_id = :id"
            ),
            {"id": str(member_id)},
        )
        return int(res.mappings().fetchone()["n"])


async def test_fetch_for_payer_lands_the_charge_without_a_webhook(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)
    invoice_fetch = build_invoice_fetch(db_pool, stripe_client)

    try:
        # The op cuts a real paid Stripe invoice. The autouse conftest fixture
        # keeps the facade from auto-firing the fetch, and no webhook fires in
        # tests — so nothing is in our DB yet.
        op_start = int(time.time())
        await memberships_service.charge_card(
            MemberMembershipsChargeCardRequest(
                member_id=member.member_id,
                paid_by_member_id=member.member_id,
                gym_id=gym_id,
                amount_cents=1500,
                reason="Drop-in pass",
                paid_cash=False,
                idempotency_key=uuid4(),
            ),
        )
        assert await _invoice_count(db_pool, member.member_id) == 0
        assert await _charge_count(db_pool, member.member_id) == 0

        # Deterministically pull it from Stripe — no webhook.
        await invoice_fetch.fetch_for_payer(member.member_id, op_start)

        assert await _invoice_count(db_pool, member.member_id) == 1
        assert await _charge_count(db_pool, member.member_id) >= 1
        assert await _line_item_count(db_pool, member.member_id) >= 1

        # Idempotent: a second fetch (racing the webhook / cron) adds nothing.
        await invoice_fetch.fetch_for_payer(member.member_id, op_start)
        assert await _invoice_count(db_pool, member.member_id) == 1
        assert await _charge_count(db_pool, member.member_id) >= 1
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_charge_card_fires_the_runner_after_the_op(
    memberships_service,
    db_pool,
    gym_id,
    created,
):
    """The facade fires the post-op fetch runner with the payer + an op_start
    stamped before the op, AFTER the op returns."""
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)
    runner = memberships_service._invoice_fetch_runner
    original = runner.start_for_payer
    spy = Mock()
    runner.start_for_payer = spy
    try:
        before = int(time.time())
        await memberships_service.charge_card(
            MemberMembershipsChargeCardRequest(
                member_id=member.member_id,
                paid_by_member_id=member.member_id,
                gym_id=gym_id,
                amount_cents=1100,
                reason="Trigger test",
                paid_cash=False,
                idempotency_key=uuid4(),
            ),
        )
        spy.assert_called_once()
        payer_arg, op_start_arg = spy.call_args.args
        assert payer_arg == member.member_id
        assert before <= op_start_arg <= int(time.time())
    finally:
        runner.start_for_payer = original
        await delete_member_data(db_pool, member.member_id)
