"""Unit tests for the deterministic sync-time coupon id.

Pure logic, no Stripe. ``PaymentSyncCoupons.coupon_id`` turns a line's
effective value + mode into a deterministic id, so find-or-create reuses one
coupon per distinct value across every member on the Connect account.
"""

from uuid import uuid4

from schema.gym_discount import DiscountMode

import src.shared.db_schema_path  # noqa: F401
from src.member_memberships.schema.payment_sync_schema import (
    LineDiscountValue,
)
from src.member_memberships.service.payment_sync.payment_sync_coupons import (
    PaymentSyncCoupons,
)


def test_percent_coupon_id_uses_basis_points_and_mode() -> None:
    value = LineDiscountValue(
        discount_mode=DiscountMode.ongoing,
        percentage_off=12.5,
        contributing_ids=[uuid4()],
    )
    assert PaymentSyncCoupons.coupon_id(value) == "pct_1250_ongoing"


def test_dollar_coupon_id_uses_cents_and_mode() -> None:
    value = LineDiscountValue(
        discount_mode=DiscountMode.once,
        dollar_off=500,
        contributing_ids=[uuid4()],
    )
    assert PaymentSyncCoupons.coupon_id(value) == "amt_500_once"


def test_coupon_id_is_deterministic_for_same_value() -> None:
    a = LineDiscountValue(
        discount_mode=DiscountMode.ongoing,
        percentage_off=5.0,
    )
    b = LineDiscountValue(
        discount_mode=DiscountMode.ongoing,
        percentage_off=5.0,
    )
    assert PaymentSyncCoupons.coupon_id(a) == PaymentSyncCoupons.coupon_id(b)


def test_same_value_different_mode_distinct_coupon() -> None:
    once = LineDiscountValue(
        discount_mode=DiscountMode.once,
        percentage_off=10.0,
    )
    ongoing = LineDiscountValue(
        discount_mode=DiscountMode.ongoing,
        percentage_off=10.0,
    )
    assert PaymentSyncCoupons.coupon_id(once) != PaymentSyncCoupons.coupon_id(ongoing)


def test_fractional_percent_rounds_to_basis_points() -> None:
    """A per-unit-summed-then-divided percent can carry fractions; the id
    rounds to integer basis points (Stripe's 2-decimal limit)."""
    value = LineDiscountValue(
        discount_mode=DiscountMode.ongoing,
        percentage_off=3.333,
    )
    # 3.333 * 100 = 333.3 -> round -> 333.
    assert PaymentSyncCoupons.coupon_id(value) == "pct_333_ongoing"
