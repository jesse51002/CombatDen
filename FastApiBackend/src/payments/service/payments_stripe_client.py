import stripe
from stripe import RequestOptions


class PaymentsStripeClient:
    """Configured Stripe client for platform-level API calls.

    Registered as a Singleton in the DI container. Provides the
    underlying StripeClient and Connect request options.
    """

    def __init__(self, secret_key: str) -> None:
        self._client = stripe.StripeClient(secret_key)

    @property
    def client(self) -> stripe.StripeClient:
        """Return the underlying StripeClient instance."""
        return self._client

    @staticmethod
    def connect_opts(stripe_account_id: str) -> stripe.RequestOptions:
        """Build Stripe Connect request options."""
        return RequestOptions(stripe_account=stripe_account_id)
