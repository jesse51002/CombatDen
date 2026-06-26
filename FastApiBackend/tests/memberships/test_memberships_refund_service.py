"""Unit tests for MemberMembershipsRefund — validation + card/cash branching.

The DB pool, the Stripe payment primitive, and the gym-account resolver are all
mocked, so these tests exercise the service's own logic (refundable math, the
card-vs-cash split, the pending-refund gate) without a real DB or Stripe.
"""

from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest
from schema.member_charge import ChargeStatus

from src.memberships.memberships_schema import MemberMembershipsRefundRequest
from src.memberships.service.memberships_refund import MemberMembershipsRefund
from src.payments.schema.payments_payment_schema import PaymentsRefundResponse


def _result(row: dict | None) -> MagicMock:
    """A SQLAlchemy result double whose mappings().fetchone() yields ``row``."""
    result = MagicMock()
    result.mappings.return_value.fetchone.return_value = row
    return result


def _charge_row(
    *,
    amount: int = 3000,
    already_refunded: int = 0,
    kind: str = "payment",
    status: str = "succeeded",
    stripe_charge_id: str | None = "ch_test",
    payment_method_type: str | None = "card",
) -> dict:
    """A member_charge_by_id.sql row double."""
    return {
        "charge_id": uuid4(),
        "invoice_id": uuid4(),
        "charge_paid_by_member_id": uuid4(),
        "gym_id": uuid4(),
        "kind": kind,
        "status": status,
        "amount": amount,
        "currency": "usd",
        "stripe_charge_id": stripe_charge_id,
        "payment_method_type": payment_method_type,
        "card_last_four": "4242" if stripe_charge_id else None,
        "already_refunded": already_refunded,
    }


def _service(db_pool_mock: MagicMock) -> tuple:
    """Build the service with mocked payment + gym-stripe deps."""
    payments = MagicMock()
    payments.refund_payment = AsyncMock()
    gym_stripe = MagicMock()
    gym_stripe.get_stripe_account_id = AsyncMock(return_value="acct_test")
    service = MemberMembershipsRefund(
        db_pool=db_pool_mock,
        payment_service=payments,
        gym_stripe_service=gym_stripe,
    )
    return service, payments, gym_stripe


def _refund_resp(amount: int, status: str = "succeeded") -> PaymentsRefundResponse:
    return PaymentsRefundResponse(
        stripe_refund_id="re_test",
        stripe_charge_id="ch_test",
        amount=amount,
        status=status,
        currency="usd",
        created=1700000000,
    )


def _req(charge_id, amount: int | None = None) -> MemberMembershipsRefundRequest:
    return MemberMembershipsRefundRequest(
        member_id=uuid4(),
        charge_id=charge_id,
        amount=amount,
        idempotency_key="k",
    )


async def test_full_card_refund(db_pool_mock: MagicMock):
    service, payments, gym_stripe = _service(db_pool_mock)
    session = db_pool_mock.session.return_value
    charge = _charge_row(amount=3000)
    session.execute.side_effect = [
        _result(charge),  # load
        _result({"amount": 3000}),  # FOR UPDATE lock re-read
        _result({"already_refunded": 0}),  # refunded-total under lock
        _result({"charge_id": uuid4()}),  # insert
    ]
    payments.refund_payment.return_value = _refund_resp(3000)

    resp = await service.refund_charge(_req(charge["charge_id"]))

    gym_stripe.get_stripe_account_id.assert_awaited_once_with(charge["gym_id"])
    req = payments.refund_payment.await_args.args[0]
    assert req.stripe_charge_id == "ch_test"
    assert req.amount == 3000  # full = refundable
    assert resp.payment_method == "card"
    assert resp.status == ChargeStatus.succeeded
    assert resp.refunded_amount == 3000
    assert resp.refund_charge_id is not None


async def test_partial_card_refund(db_pool_mock: MagicMock):
    service, payments, _ = _service(db_pool_mock)
    session = db_pool_mock.session.return_value
    charge = _charge_row(amount=5000)
    session.execute.side_effect = [
        _result(charge),  # load
        _result({"amount": 5000}),  # FOR UPDATE lock re-read
        _result({"already_refunded": 0}),  # refunded-total under lock
        _result({"charge_id": uuid4()}),  # insert
    ]
    payments.refund_payment.return_value = _refund_resp(2000)

    resp = await service.refund_charge(_req(charge["charge_id"], amount=2000))

    assert payments.refund_payment.await_args.args[0].amount == 2000
    assert resp.refunded_amount == 2000


async def test_partial_refund_respects_already_refunded(db_pool_mock: MagicMock):
    service, payments, _ = _service(db_pool_mock)
    session = db_pool_mock.session.return_value
    # 3000 charged, 1000 already refunded → 2000 refundable.
    charge = _charge_row(amount=3000, already_refunded=1000)
    session.execute.side_effect = [_result(charge)]

    with pytest.raises(ValueError, match="exceeds"):
        await service.refund_charge(_req(charge["charge_id"], amount=2500))
    payments.refund_payment.assert_not_awaited()


async def test_over_refund_rejected(db_pool_mock: MagicMock):
    service, payments, _ = _service(db_pool_mock)
    session = db_pool_mock.session.return_value
    session.execute.side_effect = [_result(_charge_row(amount=3000))]

    with pytest.raises(ValueError, match="exceeds"):
        await service.refund_charge(_req(uuid4(), amount=4000))
    payments.refund_payment.assert_not_awaited()


async def test_already_fully_refunded(db_pool_mock: MagicMock):
    service, _, _ = _service(db_pool_mock)
    session = db_pool_mock.session.return_value
    session.execute.side_effect = [
        _result(_charge_row(amount=3000, already_refunded=3000))
    ]

    with pytest.raises(ValueError, match="already been fully refunded"):
        await service.refund_charge(_req(uuid4()))


async def test_cash_refund_records_without_stripe(db_pool_mock: MagicMock):
    service, payments, gym_stripe = _service(db_pool_mock)
    session = db_pool_mock.session.return_value
    charge = _charge_row(stripe_charge_id=None, payment_method_type="cash")
    session.execute.side_effect = [
        _result(charge),  # load
        _result({"amount": 3000}),  # FOR UPDATE lock re-read
        _result({"already_refunded": 0}),  # refunded-total under lock
        _result({"charge_id": uuid4()}),  # insert
    ]

    resp = await service.refund_charge(_req(charge["charge_id"]))

    payments.refund_payment.assert_not_awaited()
    gym_stripe.get_stripe_account_id.assert_not_awaited()
    assert resp.payment_method == "cash"
    assert resp.status == ChargeStatus.succeeded
    assert resp.refunded_amount == 3000


async def test_pending_card_refund_not_recorded(db_pool_mock: MagicMock):
    service, payments, _ = _service(db_pool_mock)
    session = db_pool_mock.session.return_value
    charge = _charge_row(amount=3000)
    # Only the load runs; no insert for a pending refund.
    session.execute.side_effect = [_result(charge)]
    payments.refund_payment.return_value = _refund_resp(3000, status="pending")

    resp = await service.refund_charge(_req(charge["charge_id"]))

    assert resp.status == ChargeStatus.pending
    assert resp.refund_charge_id is None  # webhook records it on success
    assert session.execute.await_count == 1  # load only, no insert


async def test_charge_not_found(db_pool_mock: MagicMock):
    service, _, _ = _service(db_pool_mock)
    session = db_pool_mock.session.return_value
    session.execute.side_effect = [_result(None)]

    with pytest.raises(ValueError, match="not found"):
        await service.refund_charge(_req(uuid4()))


async def test_non_succeeded_charge_rejected(db_pool_mock: MagicMock):
    service, _, _ = _service(db_pool_mock)
    session = db_pool_mock.session.return_value
    session.execute.side_effect = [_result(_charge_row(status="failed"))]

    with pytest.raises(ValueError, match="succeeded payment"):
        await service.refund_charge(_req(uuid4()))


# --------------------------------------------------------------------------- #
# C-081 — concurrent over-refund guard (``_assert_refundable_under_lock``)
# C-082 — unmodeled Stripe refund status mapping (``_safe_charge_status``)
# --------------------------------------------------------------------------- #
def _make_refund_service() -> MemberMembershipsRefund:
    return MemberMembershipsRefund(
        db_pool=MagicMock(),
        payment_service=MagicMock(),
        gym_stripe_service=MagicMock(),
    )


def _session_returning(*rows: dict) -> MagicMock:
    """A fake AsyncSession whose successive execute() calls yield ``rows``."""
    session = MagicMock()
    results = []
    for row in rows:
        result = MagicMock()
        result.mappings.return_value.fetchone.return_value = row
        results.append(result)
    session.execute = AsyncMock(side_effect=results)
    return session


@pytest.mark.parametrize(
    "stripe_status, expected",
    [
        ("succeeded", ChargeStatus.succeeded),
        ("pending", ChargeStatus.pending),
        ("failed", ChargeStatus.failed),
        ("requires_action", ChargeStatus.pending),
        ("canceled", ChargeStatus.pending),
        ("something_new_from_stripe", ChargeStatus.pending),
    ],
)
def test_safe_charge_status_maps_unmodeled_to_pending(
    stripe_status: str, expected: ChargeStatus
) -> None:
    assert (
        MemberMembershipsRefund._safe_charge_status(stripe_status) == expected
    )


async def test_lock_recheck_blocks_already_fully_refunded() -> None:
    """The loser of a concurrent cash refund sees already_refunded == amount."""
    service = _make_refund_service()
    session = _session_returning({"amount": 10000}, {"already_refunded": 10000})
    with pytest.raises(ValueError, match="already been fully refunded"):
        await service._assert_refundable_under_lock(
            session, charge_id=uuid4(), amount=10000
        )


async def test_lock_recheck_blocks_amount_over_remaining() -> None:
    service = _make_refund_service()
    session = _session_returning({"amount": 10000}, {"already_refunded": 8000})
    with pytest.raises(ValueError, match="exceeds the 2000 refundable balance"):
        await service._assert_refundable_under_lock(
            session, charge_id=uuid4(), amount=5000
        )


async def test_lock_recheck_allows_within_remaining() -> None:
    service = _make_refund_service()
    session = _session_returning({"amount": 10000}, {"already_refunded": 8000})
    # 2000 remaining, refunding exactly 2000 is allowed (no raise).
    await service._assert_refundable_under_lock(
        session, charge_id=uuid4(), amount=2000
    )


async def test_lock_recheck_charge_vanished() -> None:
    service = _make_refund_service()
    session = _session_returning(None)
    with pytest.raises(ValueError, match="Charge not found"):
        await service._assert_refundable_under_lock(
            session, charge_id=uuid4(), amount=1000
        )


def test_lock_sql_uses_for_update() -> None:
    """The serialization guard must actually take a row lock."""
    from src.memberships import SQL_DIR
    from src.shared.sql_loader import load_sql

    sql = load_sql(SQL_DIR / "member_charge_lock.sql")
    assert "FOR UPDATE" in sql.upper()
