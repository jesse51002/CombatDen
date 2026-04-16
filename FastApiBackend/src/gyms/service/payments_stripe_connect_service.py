"""Stripe Connect Express account + AccountLink wrapper."""

from datetime import UTC, datetime
from uuid import UUID

import stripe
from stripe import RequestOptions

from src.core.config import settings
from src.payments.payments_exceptions import (
    PaymentsInvalidRequestError,
    PaymentsResourceNotFoundError,
)
from src.payments.schema.payments_enums import StripeResourceType
from src.payments.service.payments_stripe_client import PaymentsStripeClient

GYM_ACCOUNT_IDEMPOTENCY_PREFIX = "gym_account_"
STRIPE_EXPRESS_ACCOUNT_TYPE = "express"
STRIPE_ONBOARDING_LINK_TYPE = "account_onboarding"
STRIPE_BUSINESS_TYPE_COMPANY = "company"


class PaymentsStripeConnectService:
    """Thin wrapper over ``stripe.Account`` + ``stripe.AccountLink``.

    All three operations are platform-level Stripe calls — they
    target a connected account via the account id in the params,
    not via ``RequestOptions(stripe_account=...)``.
    """

    def __init__(self, stripe_client: PaymentsStripeClient) -> None:
        self._client = stripe_client
        self._stripe = stripe_client.client

    async def create_express_account(
        self,
        gym_id: UUID,
        owner_email: str,
    ) -> str:
        """Create a Stripe Express Connect account for a gym.

        Uses an idempotency key derived from the gym id so that a
        retry after a network blip cannot mint a second account.

        Args:
            gym_id: The CRM gym PK, stored as ``metadata.crm_gym_id``.
            owner_email: The gym owner's email, pre-filled in the
                hosted onboarding flow.

        Returns:
            The newly created ``acct_XXX`` account id.

        Raises:
            PaymentsInvalidRequestError: If Stripe rejects the
                parameters (validation error).
        """
        opts = RequestOptions(
            idempotency_key=f"{GYM_ACCOUNT_IDEMPOTENCY_PREFIX}{gym_id}",
        )
        try:
            account = await self._stripe.v1.accounts.create_async(
                params={
                    "type": STRIPE_EXPRESS_ACCOUNT_TYPE,
                    "country": settings.stripe_connect_express_country,
                    "email": owner_email,
                    "business_type": STRIPE_BUSINESS_TYPE_COMPANY,
                    "capabilities": {
                        "card_payments": {"requested": True},
                        "transfers": {"requested": True},
                    },
                    "metadata": {"crm_gym_id": str(gym_id)},
                },
                options=opts,
            )
        except stripe.InvalidRequestError as exc:
            raise PaymentsInvalidRequestError(
                f"Stripe rejected Express account create for gym {gym_id}: {exc}",
                stripe_error_code=getattr(exc, "code", None),
            ) from exc

        return account.id

    async def create_account_link(
        self,
        stripe_account_id: str,
    ) -> tuple[str, datetime]:
        """Create a short-lived hosted onboarding URL.

        The returned URL expires in ~5 minutes and should be treated
        as single-use by the caller.

        Args:
            stripe_account_id: The connected ``acct_XXX`` id.

        Returns:
            A ``(url, expires_at_utc)`` tuple.

        Raises:
            PaymentsInvalidRequestError: If Stripe rejects the link
                request (e.g. account id malformed or already
                rejected).
            PaymentsResourceNotFoundError: If the account does not
                exist on the Stripe side.
        """
        try:
            link = await self._stripe.v1.account_links.create_async(
                params={
                    "account": stripe_account_id,
                    "refresh_url": settings.stripe_connect_refresh_url,
                    "return_url": settings.stripe_connect_return_url,
                    "type": STRIPE_ONBOARDING_LINK_TYPE,
                },
            )
        except stripe.InvalidRequestError as exc:
            code = getattr(exc, "code", None)
            if code == "resource_missing":
                raise PaymentsResourceNotFoundError(
                    f"Stripe account {stripe_account_id} not found",
                    resource_id=stripe_account_id,
                    resource_type=StripeResourceType.account,
                    stripe_error_code=code,
                ) from exc
            raise PaymentsInvalidRequestError(
                f"Stripe rejected AccountLink create for {stripe_account_id}: {exc}",
                stripe_error_code=code,
            ) from exc

        expires_at = datetime.fromtimestamp(link.expires_at, tz=UTC)
        return link.url, expires_at

    async def retrieve_account(
        self,
        stripe_account_id: str,
    ) -> stripe.Account:
        """Retrieve a connected account's full state.

        Args:
            stripe_account_id: The connected ``acct_XXX`` id.

        Returns:
            The Stripe Account object with ``details_submitted``,
            ``charges_enabled``, ``payouts_enabled`` and
            ``requirements``.

        Raises:
            PaymentsResourceNotFoundError: If the account does not
                exist on the Stripe side (``resource_missing``).
            PaymentsInvalidRequestError: On any other Stripe
                validation error. Only ``resource_missing`` triggers
                the "clear CRM linkage" path — other codes must not.
        """
        try:
            account = await self._stripe.v1.accounts.retrieve_async(
                stripe_account_id,
            )
        except stripe.InvalidRequestError as exc:
            code = getattr(exc, "code", None)
            if code == "resource_missing":
                raise PaymentsResourceNotFoundError(
                    f"Stripe account {stripe_account_id} not found",
                    resource_id=stripe_account_id,
                    resource_type=StripeResourceType.account,
                    stripe_error_code=code,
                ) from exc
            raise PaymentsInvalidRequestError(
                f"Stripe rejected Account retrieve for {stripe_account_id}: {exc}",
                stripe_error_code=code,
            ) from exc

        return account
