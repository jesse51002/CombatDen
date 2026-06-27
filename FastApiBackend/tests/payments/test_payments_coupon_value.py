"""Unit tests for the deterministic value→coupon find-or-create.

Pure logic, no Stripe. ``PaymentsStripeDiscountService.coupon_id_for_value`` turns
a discount value into a deterministic id, so find-or-create reuses one coupon per
distinct value across every member on the Connect account. This is the single
value→coupon mechanism shared by the recurring sync and one-time membership
discounting.
"""

from unittest.mock import AsyncMock

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
    svc.delete_discount = AsyncMock()
    return svc


# ── coupon_id_for_value (deterministic id) ──────────────────────────


def test_percent_coupon_id_uses_basis_points() -> None:
    value = PaymentsCouponValue(percentage_off=12.5)
    assert PaymentsStripeDiscountService.coupon_id_for_value(value) == "pct_1250"


def test_dollar_coupon_id_uses_cents() -> None:
    value = PaymentsCouponValue(dollar_off=500)
    assert PaymentsStripeDiscountService.coupon_id_for_value(value) == "amt_500"


def test_coupon_id_is_deterministic_for_same_value() -> None:
    a = PaymentsCouponValue(percentage_off=5.0)
    b = PaymentsCouponValue(percentage_off=5.0)
    assert (
        PaymentsStripeDiscountService.coupon_id_for_value(a)
        == PaymentsStripeDiscountService.coupon_id_for_value(b)
    )


def test_fractional_percent_rounds_to_basis_points() -> None:
    """A per-unit-summed-then-divided percent can carry fractions; the id rounds
    to integer basis points (Stripe's 2-decimal limit)."""
    value = PaymentsCouponValue(percentage_off=3.333)
    # 3.333 * 100 = 333.3 -> round -> 333.
    assert PaymentsStripeDiscountService.coupon_id_for_value(value) == "pct_333"


# ── _matches_value (validate-or-replace guard) ──────────────────────


def test_matches_value_percent_match() -> None:
    value = PaymentsCouponValue(percentage_off=10.0)
    coupon = _coupon_resp(duration=StripeCouponDuration.forever, percentage_off=10.0)
    assert PaymentsStripeDiscountService._matches_value(coupon, value) is True


def test_matches_value_percent_value_mismatch() -> None:
    value = PaymentsCouponValue(percentage_off=10.0)
    coupon = _coupon_resp(duration=StripeCouponDuration.forever, percentage_off=12.0)
    assert PaymentsStripeDiscountService._matches_value(coupon, value) is False


def test_matches_value_duration_mismatch() -> None:
    """A coupon with a non-forever duration under the same id is a mismatch
    (must be replaced) — every coupon should be ``forever``."""
    value = PaymentsCouponValue(percentage_off=10.0)
    coupon = _coupon_resp(duration=StripeCouponDuration.once, percentage_off=10.0)
    assert PaymentsStripeDiscountService._matches_value(coupon, value) is False


def test_matches_value_dollar_match() -> None:
    value = PaymentsCouponValue(dollar_off=500)
    coupon = _coupon_resp(duration=StripeCouponDuration.forever, amount_off=500)
    assert PaymentsStripeDiscountService._matches_value(coupon, value) is True


def test_matches_value_dollar_mismatch() -> None:
    value = PaymentsCouponValue(dollar_off=500)
    coupon = _coupon_resp(duration=StripeCouponDuration.forever, amount_off=400)
    assert PaymentsStripeDiscountService._matches_value(coupon, value) is False


# ── find_or_create_for_value (find → validate → reuse/replace/create) ─


async def test_find_or_create_reuses_matching_coupon() -> None:
    """A coupon that already exists with the right value is reused — no
    delete, no create."""
    value = PaymentsCouponValue(percentage_off=10.0)
    svc = _service()
    svc.find_discount.return_value = _coupon_resp(
        duration=StripeCouponDuration.forever, percentage_off=10.0
    )

    result = await svc.find_or_create_for_value(value, "acct_test")

    assert result == "pct_1000"
    svc.delete_discount.assert_not_awaited()


async def test_find_or_create_replaces_mismatched_coupon() -> None:
    """A coupon under the id with the WRONG value is deleted + recreated."""
    value = PaymentsCouponValue(percentage_off=10.0)
    svc = _service()
    svc.find_discount.return_value = _coupon_resp(
        duration=StripeCouponDuration.forever, percentage_off=99.0
    )
    svc._create_coupon = AsyncMock(return_value="pct_1000")

    result = await svc.find_or_create_for_value(value, "acct_test")

    assert result == "pct_1000"
    svc.delete_discount.assert_awaited_once()
    svc._create_coupon.assert_awaited_once()


async def test_find_or_create_creates_when_absent() -> None:
    """No existing coupon → create it (no delete)."""
    value = PaymentsCouponValue(dollar_off=500)
    svc = _service()
    svc.find_discount.return_value = None
    svc._create_coupon = AsyncMock(return_value="amt_500")

    result = await svc.find_or_create_for_value(value, "acct_test")

    assert result == "amt_500"
    svc.delete_discount.assert_not_awaited()
    svc._create_coupon.assert_awaited_once()
