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


class PaymentsInvalidRequestError(PaymentsStripeError):
    """Invalid parameters sent to Stripe."""


class StripeOrphanError(Exception):
    """Stripe resource created but DB update failed after retries.

    The Stripe resource exists but the CRM row still has a NULL
    stripe ID. The stripe resource type and ID are included
    prominently so operators can locate and clean up the orphan.
    """

    def __init__(
        self,
        stripe_resource_type: StripeResourceType,
        stripe_id: str,
        crm_pk: str,
    ) -> None:
        self.stripe_resource_type = stripe_resource_type
        self.stripe_id = stripe_id
        self.crm_pk = crm_pk
        super().__init__(
            f"ORPHANED STRIPE RESOURCE: "
            f"type={stripe_resource_type.value}, "
            f"stripe_id={stripe_id}, crm_pk={crm_pk}. "
            f"Stripe resource exists but CRM row has NULL stripe ID."
        )
