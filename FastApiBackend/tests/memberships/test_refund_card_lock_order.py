"""F2 regression — the card-refund double-refund race.

A card refund must take the charge-row FOR-UPDATE lock and re-check the
refundable balance BEFORE it calls Stripe, all in ONE transaction. Otherwise two
concurrent refunds each call Stripe (distinct idempotency keys) and the member is
refunded twice; the DB lock then only blocks the second ROW write, too late.

Pure unit tests (no DB / Stripe / network): the db_pool session and
``_payments.refund_payment`` are mocked; ordering is asserted via a shared call
log, and the blocked-recheck path asserts Stripe is never reached.
"""

from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest

from src.memberships.service.memberships_refund import MemberMembershipsRefund


def _result_with_row(row: dict | None) -> MagicMock:
    """A SQLAlchemy result whose ``.mappings().fetchone()`` yields ``row``."""
    result = MagicMock()
    mappings = MagicMock()
    mappings.fetchone = MagicMock(return_value=row)
    result.mappings = MagicMock(return_value=mappings)
    return result


def _refund_response() -> MagicMock:
    """A succeeded Stripe refund response double."""
    refund = MagicMock()
    refund.status = "succeeded"
    refund.amount = 5000
    refund.stripe_refund_id = "re_test"
    refund.created = 1_700_000_000
    return refund


def _charge() -> dict:
    """A card charge row (has a ``stripe_charge_id``)."""
    return {
        "charge_id": uuid4(),
        "gym_id": uuid4(),
        "invoice_id": uuid4(),
        "charge_paid_by_member_id": uuid4(),
        "stripe_charge_id": "ch_test",
        "payment_method_type": "card",
        "card_last_four": "4242",
        "currency": "usd",
    }


def _build_service(
    execute_side_effect,
    refund_side_effect,
) -> MemberMembershipsRefund:
    """Wire a refund service whose session + Stripe call are mocked."""
    session = MagicMock()
    session.execute = AsyncMock(side_effect=execute_side_effect)
    session.commit = AsyncMock()
    cm = MagicMock()
    cm.__aenter__ = AsyncMock(return_value=session)
    cm.__aexit__ = AsyncMock(return_value=False)
    db_pool = MagicMock()
    db_pool.session = MagicMock(return_value=cm)

    payments = MagicMock()
    payments.refund_payment = AsyncMock(side_effect=refund_side_effect)

    gym_stripe = MagicMock()
    gym_stripe.get_stripe_account_id = AsyncMock(return_value="acct_test")

    return MemberMembershipsRefund(db_pool, payments, gym_stripe)


@pytest.mark.asyncio
async def test_lock_and_recheck_run_before_stripe_refund() -> None:
    """The FOR-UPDATE lock + refundable recheck precede the Stripe call, and the
    insert follows it — all in the one open transaction."""
    calls: list[str] = []

    async def execute_side_effect(clause, params=None) -> MagicMock:
        sql = str(clause)
        if "FOR UPDATE" in sql:
            calls.append("lock")
            return _result_with_row({"amount": 5000})
        if "already_refunded" in sql:
            calls.append("recheck")
            return _result_with_row({"already_refunded": 0})
        if "INSERT INTO member_charges" in sql:
            calls.append("insert")
            return _result_with_row({"charge_id": uuid4()})
        return _result_with_row(None)

    async def refund_side_effect(_request, _account_id) -> MagicMock:
        calls.append("stripe_refund")
        return _refund_response()

    service = _build_service(execute_side_effect, refund_side_effect)

    await service._refund_card(_charge(), 5000, "idem-key")

    # Lock + recheck happen, THEN Stripe, THEN the row insert.
    assert calls.index("lock") < calls.index("stripe_refund")
    assert calls.index("recheck") < calls.index("stripe_refund")
    assert calls.index("stripe_refund") < calls.index("insert")


@pytest.mark.asyncio
async def test_blocked_recheck_skips_stripe_and_insert() -> None:
    """When the under-lock recheck sees the charge already fully refunded, the
    Stripe refund is NEVER issued and no refund row is inserted (the second of
    two racing refunds takes exactly this path)."""

    async def execute_side_effect(clause, params=None) -> MagicMock:
        sql = str(clause)
        if "FOR UPDATE" in sql:
            return _result_with_row({"amount": 5000})
        if "already_refunded" in sql:
            # Already fully refunded by the first (committed) refund.
            return _result_with_row({"already_refunded": 5000})
        if "INSERT INTO member_charges" in sql:
            pytest.fail("insert must not run when the recheck blocks")
        return _result_with_row(None)

    async def refund_side_effect(_request, _account_id) -> MagicMock:
        pytest.fail("Stripe refund must not run when the recheck blocks")

    service = _build_service(execute_side_effect, refund_side_effect)

    with pytest.raises(ValueError, match="already been fully refunded"):
        await service._refund_card(_charge(), 5000, "idem-key")

    service._payments.refund_payment.assert_not_awaited()
