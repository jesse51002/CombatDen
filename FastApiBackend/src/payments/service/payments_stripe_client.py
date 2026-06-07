import stripe
from stripe import RequestOptions


class PaymentsStripeClient:
    """Configured Stripe client for platform-level API calls.

    Registered as a Singleton in the DI container. Provides the
    underlying StripeClient and Connect request options.
    """

    def __init__(self, secret_key: str, api_version: str) -> None:
        # Pin the API version explicitly so an SDK upgrade can't silently
        # change request/response shapes (see Settings.stripe_api_version).
        self._client = stripe.StripeClient(
            secret_key, stripe_version=api_version
        )

    @property
    def client(self) -> stripe.StripeClient:
        """Return the underlying StripeClient instance."""
        return self._client

    @staticmethod
    def connect_opts(
        stripe_account_id: str,
        *,
        idempotency_key: str | None = None,
    ) -> stripe.RequestOptions:
        """Build Stripe Connect request options for a WRITE call.

        ``idempotency_key`` is optional. Money-moving flows (invoices,
        charges, subscriptions) must pass one so Stripe dedups retries
        at the protocol level. Non-money-moving writes (product,
        price, coupon, customer CRUD) may omit it.
        """
        if idempotency_key is not None:
            return RequestOptions(
                stripe_account=stripe_account_id,
                idempotency_key=idempotency_key,
            )
        return RequestOptions(stripe_account=stripe_account_id)

    @staticmethod
    def connect_opts_readonly(
        stripe_account_id: str,
    ) -> stripe.RequestOptions:
        """Build Stripe Connect request options for a READ-ONLY call.

        Used by retrieve/list/preview paths where no idempotency key
        is meaningful.
        """
        return RequestOptions(stripe_account=stripe_account_id)
