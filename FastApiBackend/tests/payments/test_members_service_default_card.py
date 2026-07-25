"""``PaymentsStripeMembersService.update_customer`` — the card-swap contract.

Regression test for C-042: it must NOT detach the customer's previous default
payment method when the caller passes that same payment method as the new
``payment_method_id``. Detaching it would strip the card that was just set as
default, leaving the customer with no payment method.

Plus the attach's IDEMPOTENCY KEY. Every external write carries a deterministic
key so a retry cannot fire the write twice; this request carries no
caller-supplied key, so it is derived from the (customer, payment method) pair —
the two ids that fully identify the attach — suffixed ``:attach`` like the
sibling ``attach_payment_method``'s callers build theirs.

Pure unit test: the Stripe SDK and Connect client are mocked, no network.
"""

from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import pytest

from src.payments.schema.metadata.stripe_customer_metadata import (
    StripeCustomerMetadata,
)
from src.payments.schema.payments_members_schema import (
    PaymentsCustomerUpdateRequest,
)
from src.payments.service.payments_stripe_client import PaymentsStripeClient
from src.payments.service.payments_stripe_members_service import (
    PaymentsStripeMembersService,
)

CUSTOMER_ID = "cus_test"
STRIPE_ACCOUNT_ID = "acct_test"


def _build_service(
    default_pm_id: str | None,
) -> tuple[PaymentsStripeMembersService, MagicMock]:
    """Wire a service whose mocked customer has ``default_pm_id`` as default."""
    customer = SimpleNamespace(
        id=CUSTOMER_ID,
        name="Jane",
        email="jane@example.com",
        phone=None,
        deleted=False,
        invoice_settings=SimpleNamespace(
            default_payment_method=default_pm_id,
        ),
    )
    new_pm = SimpleNamespace(
        id="pm_new",
        card=SimpleNamespace(
            brand="visa", last4="4242", exp_month=12, exp_year=2030
        ),
    )

    stripe = MagicMock()
    stripe.v1.customers.retrieve_async = AsyncMock(return_value=customer)
    stripe.v1.customers.update_async = AsyncMock(return_value=customer)
    stripe.v1.payment_methods.attach_async = AsyncMock()
    stripe.v1.payment_methods.detach_async = AsyncMock()
    stripe.v1.payment_methods.retrieve_async = AsyncMock(return_value=new_pm)

    client = MagicMock()
    client.client = stripe
    # The REAL options builder, so the idempotency key the service derives is
    # actually visible on the recorded call (a stubbed `{}` would hide it).
    client.connect_opts = PaymentsStripeClient.connect_opts

    return PaymentsStripeMembersService(client), stripe


def _request(payment_method_id: str) -> PaymentsCustomerUpdateRequest:
    return PaymentsCustomerUpdateRequest(
        stripe_customer_id=CUSTOMER_ID,
        name="Jane",
        payment_method_id=payment_method_id,
        metadata=StripeCustomerMetadata(
            member_id="11111111-1111-1111-1111-111111111111",
            gym_id="22222222-2222-2222-2222-222222222222",
        ),
    )


@pytest.mark.asyncio
async def test_update_customer_skips_detach_when_same_as_default() -> None:
    """Passing the current default as the new PM must not detach it."""
    service, stripe = _build_service(default_pm_id="pm_same")

    await service.update_customer(_request("pm_same"), STRIPE_ACCOUNT_ID)

    stripe.v1.payment_methods.detach_async.assert_not_called()


@pytest.mark.asyncio
async def test_update_customer_detaches_when_default_differs() -> None:
    """A genuinely new PM still detaches the old default."""
    service, stripe = _build_service(default_pm_id="pm_old")

    await service.update_customer(_request("pm_new"), STRIPE_ACCOUNT_ID)

    stripe.v1.payment_methods.detach_async.assert_awaited_once()
    args, _ = stripe.v1.payment_methods.detach_async.call_args
    assert args[0] == "pm_old"


@pytest.mark.asyncio
async def test_update_customer_no_detach_when_no_prior_default() -> None:
    """No prior default means nothing to detach."""
    service, stripe = _build_service(default_pm_id=None)

    await service.update_customer(_request("pm_new"), STRIPE_ACCOUNT_ID)

    stripe.v1.payment_methods.detach_async.assert_not_called()


@pytest.mark.asyncio
async def test_update_customer_attach_carries_a_deterministic_key() -> None:
    """The attach must carry a deterministic idempotency key.

    Without one, a retried card update (a double-tapped Save, a client retry
    after a timeout) fires a second unguarded attach against Stripe. The key is
    derived from the (customer, payment method) pair — the two ids that fully
    identify this write — with the ``:attach`` suffix the sibling
    ``attach_payment_method``'s callers use, so the same card update dedups and a
    genuinely different card still attaches.
    """
    service, stripe = _build_service(default_pm_id="pm_old")

    await service.update_customer(_request("pm_new"), STRIPE_ACCOUNT_ID)

    options = stripe.v1.payment_methods.attach_async.await_args.kwargs["options"]
    assert options["stripe_account"] == STRIPE_ACCOUNT_ID
    assert options["idempotency_key"] == f"{CUSTOMER_ID}:pm_new:attach"


@pytest.mark.asyncio
async def test_update_customer_attach_key_is_stable_across_retries() -> None:
    """The same card update derives the SAME key twice — that is what dedups."""
    keys = []
    for _ in range(2):
        service, stripe = _build_service(default_pm_id="pm_old")
        await service.update_customer(_request("pm_new"), STRIPE_ACCOUNT_ID)
        keys.append(
            stripe.v1.payment_methods.attach_async.await_args.kwargs["options"][
                "idempotency_key"
            ]
        )

    assert keys[0] == keys[1]

    # A DIFFERENT card is a different write and must not be deduped onto it.
    service, stripe = _build_service(default_pm_id="pm_old")
    await service.update_customer(_request("pm_other"), STRIPE_ACCOUNT_ID)
    other_key = stripe.v1.payment_methods.attach_async.await_args.kwargs[
        "options"
    ]["idempotency_key"]
    assert other_key != keys[0]
