"""Regression test for C-004 (G13): a line percent that rounds below Stripe's
0.01% precision must NOT be emitted as a coupon value.

A tiny positive effective percent (e.g. one small per-unit percent averaged over
a large consolidated line) used to pass the bare ``line_percent > 0`` guard, then
became ``percent_off=0.0`` under coupon id ``pct_0`` — which Stripe rejects with
an InvalidRequestError, crashing the sync. The floor at the emit point drops a
rounds-to-zero percent instead. Pure unit test over the aggregation math: no DB,
Stripe, or network.
"""

from uuid import uuid4

from src.payments.service.payments_stripe_discount_service import (
    PaymentsStripeDiscountService,
)
from src.sync.service.sync_discounts import (
    MIN_LINE_PERCENT_OFF,
    PERCENT_OFF_DECIMALS,
    PaymentSyncDiscounts,
)
from src.sync.sync_schema import ActiveMembershipRow, AppliedDiscount


def _membership(
    percentage_off: float | None = None,
    dollar_off: int | None = None,
    price: int = 10_000,
    is_frozen: bool = False,
) -> ActiveMembershipRow:
    """Build a one-discount active membership row for the aggregation."""
    discounts: list[AppliedDiscount] = []
    if percentage_off is not None or dollar_off is not None:
        discounts.append(
            AppliedDiscount(
                applied_discount_id=uuid4(),
                item_id=uuid4(),
                member_id=uuid4(),
                plan_id=uuid4(),
                percentage_off=percentage_off,
                dollar_off=dollar_off,
            )
        )
    return ActiveMembershipRow(
        item_id=uuid4(),
        member_id=uuid4(),
        plan_id=uuid4(),
        price_id=uuid4(),
        stripe_price_id="price_test",
        price=price,
        is_frozen=is_frozen,
        discounts=discounts,
    )


def _aggregate(memberships: list[ActiveMembershipRow]):
    """Run the aggregation without any Stripe client (math only)."""
    svc = PaymentSyncDiscounts(discount_service=None)  # type: ignore[arg-type]
    return svc._aggregate_line_values(memberships)


def test_rounds_to_zero_percent_is_not_emitted() -> None:
    """A 0.001% discount on one of many units rounds below 0.01% → no value.

    Effective fraction for a 0.001% discount on a single membership is ~1e-5;
    averaged over 200 units the line percent is far below Stripe's 0.01% floor,
    so it must NOT be emitted (which would have produced an invalid pct_0 coupon).
    """
    memberships = [_membership(percentage_off=0.001)]
    memberships += [_membership() for _ in range(199)]

    values, _amounts = _aggregate(memberships)

    assert values == [], "rounds-to-zero percent must not be emitted as a value"


def test_pct_0_id_would_have_been_rejected() -> None:
    """Confirms the dropped value is exactly the one Stripe rejects.

    The deterministic id for the tiny percent is ``pct_0`` and the create would
    send ``percent_off=0.0`` — a 0% coupon Stripe rejects. Locks in WHY the floor
    exists, without touching Stripe.
    """
    from src.payments.schema.payments_discount_schema import PaymentsCouponValue

    tiny = PaymentsCouponValue(percentage_off=0.001)
    assert PaymentsStripeDiscountService.coupon_id_for_value(tiny) == "pct_0"
    assert round(0.001, PERCENT_OFF_DECIMALS) == 0.0


def test_percent_at_floor_is_still_emitted() -> None:
    """A discount that rounds to exactly 0.01% stays emitted (not over-clamped).

    A single 0.01% discount on one membership gives a line percent of ~0.01%,
    which rounds to the floor and must still produce a coupon value.
    """
    values, _amounts = _aggregate([_membership(percentage_off=0.01)])

    assert len(values) == 1
    assert values[0].percentage_off is not None
    assert round(values[0].percentage_off, PERCENT_OFF_DECIMALS) >= (
        MIN_LINE_PERCENT_OFF
    )


def test_normal_percent_still_emitted() -> None:
    """A normal 25% discount is unaffected by the floor."""
    values, _amounts = _aggregate([_membership(percentage_off=25.0)])

    assert len(values) == 1
    assert values[0].percentage_off == 25.0


def test_frozen_membership_still_emits_full_percent() -> None:
    """Freeze (synthetic 100%-off) on a lone unit stays a real value."""
    values, _amounts = _aggregate([_membership(is_frozen=True)])

    assert len(values) == 1
    assert values[0].percentage_off == 100.0
