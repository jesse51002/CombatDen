"""Regression guard: a platform-minted card cannot attach to a
connected-account customer.

The whole backend runs direct-charge Stripe Connect: every customer, card, and
subscription lives on the gym's connected account —
``PaymentsStripeMembersService`` threads ``connect_opts(stripe_account_id)``
through create / update / attach. A card the browser tokenizes WITHOUT the
connected account set is a *platform-owned* payment method; attaching it to a
connected-account customer is forbidden by Stripe, so the whole card swap 500s.
That is the exact failure the kiosk signup hit 100% of the time before the CRM
began tokenizing on the gym's connected account.

This test locks the invariant so it can't silently regress: create a customer
on the connected account, mint a payment method in PLATFORM context (no
``connect_opts`` — exactly what a browser mints when the connected account is
not set on the Stripe.js client), and assert ``update_customer`` (the
``PUT /members/{id}/card`` path, and the kiosk signup's card path) raises
``stripe.InvalidRequestError``.

The seed masks this everywhere else because it uses Stripe's magic
``pm_card_visa`` token, which crosses accounts in test mode; a genuinely
platform-created pm (via ``tok_visa``) does not.
"""

import pytest
import stripe

from src.payments.schema.metadata.stripe_customer_metadata import (
    StripeCustomerMetadata,
)
from src.payments.schema.payments_members_schema import (
    PaymentsCustomerUpdateRequest,
)
from src.payments.service.payments_stripe_members_service import (
    PaymentsStripeMembersService,
)


async def test_platform_pm_cannot_attach_to_connected_customer(
    stripe_client,
    stripe_account_id,
    gym_id,
    created,
):
    # A member => a Stripe customer on the gym's CONNECTED account.
    member = await created.member(gym_id)

    # A payment method minted in PLATFORM context (no connect_opts): a genuine
    # platform-owned pm, exactly what the browser tokenizes when the connected
    # account is NOT set on the Stripe.js client. (Test PMs cannot be deleted,
    # only detached, so — like every other test pm — it is left uncleaned.)
    platform_pm = await stripe_client.client.v1.payment_methods.create_async(
        params={"type": "card", "card": {"token": "tok_visa"}},
    )

    members_service = PaymentsStripeMembersService(stripe_client)

    # Attaching a platform-owned pm to a connected-account customer is
    # forbidden by Stripe. If this stops raising, the direct-charge attach
    # invariant has regressed and the "client tokenizes on the connected
    # account" fix is no longer load-bearing.
    with pytest.raises(stripe.InvalidRequestError):
        await members_service.update_customer(
            PaymentsCustomerUpdateRequest(
                stripe_customer_id=member.stripe_customer_id,
                name="Platform PM Guard",
                payment_method_id=platform_pm.id,
                metadata=StripeCustomerMetadata(
                    member_id=member.member_id,
                    gym_id=gym_id,
                ),
            ),
            stripe_account_id,
        )
