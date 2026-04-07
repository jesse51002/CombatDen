from src.payments.schema.payments_enums import StripeResourceType


class PaymentsStripeError(Exception):
    """Base exception for Stripe API errors."""

    def __init__(
        self,
        message: str,
        stripe_error_code: str | None = None,
    ) -> None:
        super().__init__(message)
        self.stripe_error_code = stripe_error_code


class PaymentsResourceNotFoundError(PaymentsStripeError):
    """Stripe resource (product/price/coupon/subscription/customer) not found."""

    def __init__(
        self,
        message: str,
        resource_id: str | None = None,
        resource_type: StripeResourceType | None = None,
        stripe_error_code: str | None = None,
    ) -> None:
        super().__init__(message, stripe_error_code=stripe_error_code)
        self.resource_id = resource_id
        self.resource_type = resource_type


class PaymentsResourceInactiveError(PaymentsStripeError):
    """Stripe resource (price/product) is inactive or deleted."""

    def __init__(
        self,
        message: str,
        resource_id: str | None = None,
        resource_type: StripeResourceType | None = None,
        stripe_error_code: str | None = None,
    ) -> None:
        super().__init__(message, stripe_error_code=stripe_error_code)
        self.resource_id = resource_id
        self.resource_type = resource_type


class PaymentsInvalidRequestError(PaymentsStripeError):
    """Invalid parameters sent to Stripe."""
