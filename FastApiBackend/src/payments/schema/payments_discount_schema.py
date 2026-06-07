from pydantic import BaseModel, model_validator

from src.payments.schema.payments_enums import StripeCouponDuration


class PaymentsDiscountCreateRequest(BaseModel):
    """Create a Stripe Coupon with a caller-supplied deterministic id.

    The sync's value-derived coupons set their own id (``pct_<bps>_<mode>`` /
    ``amt_<cents>_<mode>``) so find-or-create is idempotent. There is no CRM
    back-reference metadata — these coupons are shared across every discount at a
    given value, computed on the spot at sync.
    """

    coupon_id: str
    discount_name: str
    percentage_off: float | None = None
    amount_off: int | None = None
    currency: str = "usd"
    duration: StripeCouponDuration
    duration_in_months: int | None = None

    @model_validator(mode="after")
    def exactly_one_discount_value(self) -> PaymentsDiscountCreateRequest:
        """Ensure exactly one of percentage_off or amount_off is set."""
        has_pct = self.percentage_off is not None
        has_amt = self.amount_off is not None
        if has_pct == has_amt:
            raise ValueError(
                "Exactly one of percentage_off or amount_off must be set",
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
