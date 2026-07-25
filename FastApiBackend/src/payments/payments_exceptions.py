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


class PaymentsNotCollectedError(PaymentsStripeError):
    """A card charge that definitively did NOT collect — with no decline raised.

    ``invoices.pay`` raises ``stripe.CardError`` on an outright refusal, but an
    off-session invoice whose PaymentIntent needs authentication (SCA / 3-D
    Secure) comes back with the invoice still ``open`` and no exception. That is
    a definitive business OUTCOME — "we could not collect on this card, staff
    must act" — the same KIND of thing as a decline, so it belongs on the same
    side of the contract: a 2xx RESULT carrying the reason (retry-card's **207**
    ``not_collected``), never a 500 that would bury real outages in monitoring.

    It is NOT a decline, though, and must never be reported as one: the bank
    never said no, so "try another card" is the wrong advice — the member has to
    complete the authentication, or staff collect another way.

    Deliberately a ``PaymentsStripeError`` subclass: any caller that has NOT
    been taught the distinction keeps mapping it to the safe, non-retryable
    500. A router that HAS must catch this type **above** its
    ``except PaymentsStripeError`` arm, or the base arm wins.
    """


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
