"""Unit tests for the deterministic value→coupon find-or-create.

Pure logic, no Stripe. ``PaymentsStripeDiscountService.coupon_id_for_value`` turns
a discount value + mode into a deterministic id, so find-or-create reuses one
coupon per distinct value across every member on the Connect account. This is the
single value→coupon mechanism shared by the recurring sync and one-time
membership discounting.
"""

from types import SimpleNamespace
from unittest.mock import AsyncMock

from schema.gym_discount import DiscountMode

import src.shared.db_schema_path  # noqa: F401
from src.payments.schema.payments_discount_schema import (
    PaymentsCouponValue,
    PaymentsDiscountResponse,
)
from src.payments.schema.payments_enums import StripeCouponDuration
from src.payments.service.payments_stripe_discount_service import (
    PaymentsStripeDiscountService,
)


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


def _service() -> PaymentsStripeDiscountService:
    """A discount service with its Stripe I/O methods mocked."""
    svc = PaymentsStripeDiscountService(AsyncMock())
    svc.find_discount = AsyncMock()
    svc.create_discount = AsyncMock()
    svc.delete_discount = AsyncMock()
    return svc


# ── coupon_id_for_value (deterministic id) ──────────────────────────


def test_percent_coupon_id_uses_basis_points_and_mode() -> None:
    value = PaymentsCouponValue(
        discount_mode=DiscountMode.ongoing,
        percentage_off=12.5,
    )
    assert (
        PaymentsStripeDiscountService.coupon_id_for_value(value)
        == "pct_1250_ongoing"
    )


def test_dollar_coupon_id_uses_cents_and_mode() -> None:
    value = PaymentsCouponValue(
        discount_mode=DiscountMode.once,
        dollar_off=500,
    )
    assert (
        PaymentsStripeDiscountService.coupon_id_for_value(value)
        == "amt_500_once"
    )


def test_coupon_id_is_deterministic_for_same_value() -> None:
    a = PaymentsCouponValue(discount_mode=DiscountMode.ongoing, percentage_off=5.0)
    b = PaymentsCouponValue(discount_mode=DiscountMode.ongoing, percentage_off=5.0)
    assert (
        PaymentsStripeDiscountService.coupon_id_for_value(a)
        == PaymentsStripeDiscountService.coupon_id_for_value(b)
    )


def test_same_value_different_mode_distinct_coupon() -> None:
    once = PaymentsCouponValue(discount_mode=DiscountMode.once, percentage_off=10.0)
    ongoing = PaymentsCouponValue(
        discount_mode=DiscountMode.ongoing, percentage_off=10.0
    )
    assert (
        PaymentsStripeDiscountService.coupon_id_for_value(once)
        != PaymentsStripeDiscountService.coupon_id_for_value(ongoing)
    )


def test_fractional_percent_rounds_to_basis_points() -> None:
    """A per-unit-summed-then-divided percent can carry fractions; the id rounds
    to integer basis points (Stripe's 2-decimal limit)."""
    value = PaymentsCouponValue(
        discount_mode=DiscountMode.ongoing,
        percentage_off=3.333,
    )
    # 3.333 * 100 = 333.3 -> round -> 333.
    assert (
        PaymentsStripeDiscountService.coupon_id_for_value(value)
        == "pct_333_ongoing"
    )


# ── _matches_value (validate-or-replace guard) ──────────────────────


def test_matches_value_percent_match() -> None:
    value = PaymentsCouponValue(
        discount_mode=DiscountMode.ongoing, percentage_off=10.0
    )
    coupon = _coupon_resp(
        duration=StripeCouponDuration.forever, percentage_off=10.0
    )
    assert PaymentsStripeDiscountService._matches_value(coupon, value) is True


def test_matches_value_percent_value_mismatch() -> None:
    value = PaymentsCouponValue(
        discount_mode=DiscountMode.ongoing, percentage_off=10.0
    )
    coupon = _coupon_resp(
        duration=StripeCouponDuration.forever, percentage_off=12.0
    )
    assert PaymentsStripeDiscountService._matches_value(coupon, value) is False


def test_matches_value_duration_mismatch() -> None:
    """An ongoing value expects a `forever` coupon — a `once` coupon under the
    same id is a mismatch (must be replaced)."""
    value = PaymentsCouponValue(
        discount_mode=DiscountMode.ongoing, percentage_off=10.0
    )
    coupon = _coupon_resp(
        duration=StripeCouponDuration.once, percentage_off=10.0
    )
    assert PaymentsStripeDiscountService._matches_value(coupon, value) is False


def test_matches_value_dollar_match() -> None:
    value = PaymentsCouponValue(discount_mode=DiscountMode.once, dollar_off=500)
    coupon = _coupon_resp(duration=StripeCouponDuration.once, amount_off=500)
    assert PaymentsStripeDiscountService._matches_value(coupon, value) is True


def test_matches_value_dollar_mismatch() -> None:
    value = PaymentsCouponValue(discount_mode=DiscountMode.once, dollar_off=500)
    coupon = _coupon_resp(duration=StripeCouponDuration.once, amount_off=400)
    assert PaymentsStripeDiscountService._matches_value(coupon, value) is False


# ── find_or_create_for_value (find → validate → reuse/replace/create) ─


async def test_find_or_create_reuses_matching_coupon() -> None:
    """A coupon that already exists with the right value is reused — no
    delete, no create."""
    value = PaymentsCouponValue(
        discount_mode=DiscountMode.ongoing, percentage_off=10.0
    )
    svc = _service()
    svc.find_discount.return_value = _coupon_resp(
        duration=StripeCouponDuration.forever, percentage_off=10.0
    )

    result = await svc.find_or_create_for_value(value, "acct_test")

    assert result == "pct_1000_ongoing"
    svc.delete_discount.assert_not_awaited()
    svc.create_discount.assert_not_awaited()


async def test_find_or_create_replaces_mismatched_coupon() -> None:
    """A coupon under the id with the WRONG value is deleted + recreated."""
    value = PaymentsCouponValue(
        discount_mode=DiscountMode.ongoing, percentage_off=10.0
    )
    svc = _service()
    svc.find_discount.return_value = _coupon_resp(
        duration=StripeCouponDuration.forever, percentage_off=99.0
    )
    svc.create_discount.return_value = SimpleNamespace(
        stripe_coupon_id="pct_1000_ongoing"
    )

    result = await svc.find_or_create_for_value(value, "acct_test")

    assert result == "pct_1000_ongoing"
    svc.delete_discount.assert_awaited_once()
    svc.create_discount.assert_awaited_once()


async def test_find_or_create_creates_when_absent() -> None:
    """No existing coupon → create it (no delete)."""
    value = PaymentsCouponValue(discount_mode=DiscountMode.once, dollar_off=500)
    svc = _service()
    svc.find_discount.return_value = None
    svc.create_discount.return_value = SimpleNamespace(
        stripe_coupon_id="amt_500_once"
    )

    result = await svc.find_or_create_for_value(value, "acct_test")

    assert result == "amt_500_once"
    svc.delete_discount.assert_not_awaited()
    svc.create_discount.assert_awaited_once()
