from __future__ import annotations

from pydantic import BaseModel, model_validator

import src.shared.db_schema_path  # noqa: F401
from src.payments.schema.payments_enums import StripeCouponDuration


class PaymentsCouponValue(BaseModel):
    """The value a deterministic coupon encodes: a percent XOR dollar.

    The shared input to the payments coupon find-or-create
    (``PaymentsStripeDiscountService.find_or_create_for_value``). Both the
    recurring sync (per consolidated line) and one-time membership discounting
    produce one of these per discount value; the deterministic coupon id is a
    pure function of it (``pct_<bps>`` / ``amt_<cents>``). Every coupon is a
    ``forever`` coupon — lifetime is enforced by our resolved ``end_date``.
    """

    percentage_off: float | None = None
    dollar_off: int | None = None

    @model_validator(mode="after")
    def _exactly_one_value(self) -> PaymentsCouponValue:
        """A coupon value is percent XOR dollar — exactly one must be set."""
        if (self.percentage_off is None) == (self.dollar_off is None):
            raise ValueError(
                "PaymentsCouponValue must set exactly one of "
                "percentage_off / dollar_off"
            )
        return self


class PaymentsDiscountDeleteRequest(BaseModel):
    """Delete a Stripe Coupon."""

    stripe_coupon_id: str


class PaymentsDiscountResponse(BaseModel):
    """Response after creating/retrieving a Stripe Coupon."""

    stripe_coupon_id: str
    name: str
    percentage_off: float | None = None
    amount_off: int | None = None
    currency: str | None = None
    duration: StripeCouponDuration
    duration_in_months: int | None = None
    valid: bool
    metadata: dict[str, str] = {}
