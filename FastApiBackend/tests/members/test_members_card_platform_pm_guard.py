"""Regression guard: a platform-minted card cannot attach to a
connected-account customer.

The backend runs direct-charge Stripe Connect — every customer, card and
subscription lives on the gym's connected account. A card tokenized WITHOUT the
connected account set is *platform-owned*, and Stripe forbids attaching one to a
connected-account customer, so the whole card swap 500s. That is what the kiosk
signup hit 100% of the time until the CRM tokenized on the gym's account.

The seed masks this everywhere else: Stripe's magic ``pm_card_visa`` token
crosses accounts in test mode, a genuine platform-created pm (``tok_visa``)
does not.
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

    # Minted in PLATFORM context (no connect_opts) — what the browser tokenizes
    # when the connected account is NOT set on the Stripe.js client. Test pms
    # can only be detached, never deleted, so this one is left uncleaned.
    platform_pm = await stripe_client.client.v1.payment_methods.create_async(
        params={"type": "card", "card": {"token": "tok_visa"}},
    )

    members_service = PaymentsStripeMembersService(stripe_client)

    # If this stops raising, the direct-charge attach invariant has regressed
    # and the "client tokenizes on the connected account" fix is no longer
    # load-bearing.
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
