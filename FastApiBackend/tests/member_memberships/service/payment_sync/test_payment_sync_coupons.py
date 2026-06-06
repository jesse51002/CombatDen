"""Unit tests for the deterministic sync-time coupon id.

Pure logic, no Stripe. ``PaymentSyncCoupons.coupon_id`` turns a line's
effective value + mode into a deterministic id, so find-or-create reuses one
coupon per distinct value across every member on the Connect account.
"""

from types import SimpleNamespace
from unittest.mock import AsyncMock
from uuid import uuid4

from schema.gym_discount import DiscountMode

import src.shared.db_schema_path  # noqa: F401
from src.member_memberships.schema.payment_sync_schema import (
    LineDiscountValue,
)
from src.member_memberships.service.payment_sync.payment_sync_coupons import (
    PaymentSyncCoupons,
)
from src.payments.schema.payments_discount_schema import (
    PaymentsDiscountResponse,
)
from src.payments.schema.payments_enums import StripeCouponDuration


def _coupon_resp(
    *,
    duration: StripeCouponDuration,
    percentage_off: float | None = None,
    amount_off: int | None = None,
) -> PaymentsDiscountResponse:
    return PaymentsDiscountResponse(
        stripe_coupon_id="existing",
        name="existing",
        percentage_off=percentage_off,
        amount_off=amount_off,
        currency="usd" if amount_off is not None else None,
        duration=duration,
        valid=True,
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


# ── _matches_value (validate-or-replace guard) ──────────────────────


def test_matches_value_percent_match() -> None:
    value = LineDiscountValue(
        discount_mode=DiscountMode.ongoing, percentage_off=10.0
    )
    coupon = _coupon_resp(
        duration=StripeCouponDuration.forever, percentage_off=10.0
    )
    assert PaymentSyncCoupons._matches_value(coupon, value) is True


def test_matches_value_percent_value_mismatch() -> None:
    value = LineDiscountValue(
        discount_mode=DiscountMode.ongoing, percentage_off=10.0
    )
    coupon = _coupon_resp(
        duration=StripeCouponDuration.forever, percentage_off=12.0
    )
    assert PaymentSyncCoupons._matches_value(coupon, value) is False


def test_matches_value_duration_mismatch() -> None:
    """An ongoing value expects a `forever` coupon — a `once` coupon under the
    same id is a mismatch (must be replaced)."""
    value = LineDiscountValue(
        discount_mode=DiscountMode.ongoing, percentage_off=10.0
    )
    coupon = _coupon_resp(
        duration=StripeCouponDuration.once, percentage_off=10.0
    )
    assert PaymentSyncCoupons._matches_value(coupon, value) is False


def test_matches_value_dollar_match() -> None:
    value = LineDiscountValue(
        discount_mode=DiscountMode.once, dollar_off=500
    )
    coupon = _coupon_resp(duration=StripeCouponDuration.once, amount_off=500)
    assert PaymentSyncCoupons._matches_value(coupon, value) is True


def test_matches_value_dollar_mismatch() -> None:
    value = LineDiscountValue(
        discount_mode=DiscountMode.once, dollar_off=500
    )
    coupon = _coupon_resp(duration=StripeCouponDuration.once, amount_off=400)
    assert PaymentSyncCoupons._matches_value(coupon, value) is False


# ── find_or_create (find → validate → reuse/replace/create) ─────────


async def test_find_or_create_reuses_matching_coupon() -> None:
    """A coupon that already exists with the right value is reused — no
    delete, no create."""
    value = LineDiscountValue(
        discount_mode=DiscountMode.ongoing, percentage_off=10.0
    )
    svc = AsyncMock()
    svc.find_discount.return_value = _coupon_resp(
        duration=StripeCouponDuration.forever, percentage_off=10.0
    )

    result = await PaymentSyncCoupons(svc).find_or_create(value, "acct_test")

    assert result == "pct_1000_ongoing"
    svc.delete_discount.assert_not_awaited()
    svc.create_discount.assert_not_awaited()


async def test_find_or_create_replaces_mismatched_coupon() -> None:
    """A coupon under the id with the WRONG value is deleted + recreated."""
    value = LineDiscountValue(
        discount_mode=DiscountMode.ongoing, percentage_off=10.0
    )
    svc = AsyncMock()
    svc.find_discount.return_value = _coupon_resp(
        duration=StripeCouponDuration.forever, percentage_off=99.0
    )
    svc.create_discount.return_value = SimpleNamespace(
        stripe_coupon_id="pct_1000_ongoing"
    )

    result = await PaymentSyncCoupons(svc).find_or_create(value, "acct_test")

    assert result == "pct_1000_ongoing"
    svc.delete_discount.assert_awaited_once()
    svc.create_discount.assert_awaited_once()


async def test_find_or_create_creates_when_absent() -> None:
    """No existing coupon → create it (no delete)."""
    value = LineDiscountValue(
        discount_mode=DiscountMode.once, dollar_off=500
    )
    svc = AsyncMock()
    svc.find_discount.return_value = None
    svc.create_discount.return_value = SimpleNamespace(
        stripe_coupon_id="amt_500_once"
    )

    result = await PaymentSyncCoupons(svc).find_or_create(value, "acct_test")

    assert result == "amt_500_once"
    svc.delete_discount.assert_not_awaited()
    svc.create_discount.assert_awaited_once()
