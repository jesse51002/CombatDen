"""Integration tests for member update operations.

Each update is paired with a billing-state guard: member edits
(name/email/card swap/unlink) must never generate an invoice or
move the customer balance on Stripe.
"""

from datetime import date

from src.members.schema.members_billing_schema import (
    MembersBillingUpdateCardRequest,
)
from src.members.schema.members_schema import (
    MemberCreateRequest,
    MemberUpdateData,
)
from tests.helpers.cleanup import delete_member_data
from tests.helpers.stripe_assertions import (
    assert_no_unexpected_charges,
    snapshot_billing_state,
)


def _default_pm_id(customer) -> str | None:
    """Resolve a customer's default payment method id, expanded or not."""
    if customer.invoice_settings is None:
        return None
    pm = customer.invoice_settings.default_payment_method
    if pm is None:
        return None
    if isinstance(pm, str):
        return pm
    return getattr(pm, "id", None)


async def test_update_personal_info(
    management_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    member = (await management_service.create_member(
        MemberCreateRequest(
            gym_id=gym_id,
            first_name="Original",
            last_name="Name",
            send_invite=False,
        ),
    )).member
    created.track_customer(member.stripe_customer_id)

    try:
        before = await snapshot_billing_state(
            stripe_client,
            member.stripe_customer_id,
            connect_opts,
        )

        resp = await management_service.update_member(
            member.member_id,
            MemberUpdateData(
                first_name="Updated",
                email="updated@test.com",
            ),
        )

        assert resp.first_name == "Updated"
        assert resp.email == "updated@test.com"
        assert resp.last_name == "Name"  # unchanged

        # update_member deliberately does NOT sync name/email to the Stripe
        # customer — the write path only touches ``member_billing_profile``.
        # The customer is still checked reachable, and unbilled.
        customer = await stripe_client.client.v1.customers.retrieve_async(
            member.stripe_customer_id,
            options=connect_opts,
        )
        assert customer.id == member.stripe_customer_id
        # Profile edit must never bill.
        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_date_of_birth_round_trips_and_survives_partial_update(
    management_service,
    db_pool,
    gym_id,
    created,
):
    """``date_of_birth`` round-trips through create + update.

    ``MemberUpdateData`` is dumped ``exclude_unset=True``, so an OMITTED field
    never reaches the SET clause while an EXPLICIT ``None`` is a real clear.
    Both directions are asserted: a regression in either silently loses or
    silently keeps a member's data.
    """
    dob = date(1990, 5, 17)
    member = (await management_service.create_member(
        MemberCreateRequest(
            gym_id=gym_id,
            first_name="Dob",
            last_name="RoundTrip",
            date_of_birth=dob,
            send_invite=False,
        ),
    )).member
    created.track_customer(member.stripe_customer_id)

    try:
        # 1. The create response echoes what was stored.
        assert member.date_of_birth == dob

        # 2. A partial update that does NOT mention date_of_birth leaves it
        #    alone — the blank-field-must-not-wipe-stored-data case.
        resp = await management_service.update_member(
            member.member_id,
            MemberUpdateData(phone="555-0100"),
        )
        assert resp.phone == "555-0100"
        assert resp.date_of_birth == dob

        # 3. A real edit changes it.
        corrected = date(1991, 1, 2)
        resp = await management_service.update_member(
            member.member_id,
            MemberUpdateData(date_of_birth=corrected),
        )
        assert resp.date_of_birth == corrected

        # 4. An EXPLICIT None clears it (distinct from omitting the field).
        resp = await management_service.update_member(
            member.member_id,
            MemberUpdateData(date_of_birth=None),
        )
        assert resp.date_of_birth is None
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_update_card_existing_customer(
    management_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    pm1 = await created.payment_method()
    created_member = (await management_service.create_member(
        MemberCreateRequest(
            gym_id=gym_id,
            first_name="Card",
            last_name="Swap",
            payment_method_id=pm1,
            send_invite=False,
        ),
    )).member
    created.track_customer(created_member.stripe_customer_id)

    try:
        pm2 = await created.payment_method()
        before = await snapshot_billing_state(
            stripe_client,
            created_member.stripe_customer_id,
            connect_opts,
        )

        resp = await management_service.update_card(
            created_member.member_id,
            MembersBillingUpdateCardRequest(
                payment_method_id=pm2,
            ),
        )

        assert resp.stripe_payment_method_id == pm2
        assert resp.card_brand == "visa"

        # Stripe side: the customer's default payment method is now pm2.
        customer = await stripe_client.client.v1.customers.retrieve_async(
            created_member.stripe_customer_id,
            options=connect_opts,
        )
        assert _default_pm_id(customer) == pm2, (
            f"Customer {created_member.stripe_customer_id} "
            f"default_payment_method not updated to {pm2}"
        )
        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, created_member.member_id)


async def test_update_card_on_cardless_customer(
    management_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """A cardless member (customer exists, no card) gets a card on update_card.

    The Stripe customer is always provisioned at creation, so update_card only
    ever attaches the payment method to the existing customer.
    """
    # Member is created with a Stripe customer but no card.
    created_member = (await management_service.create_member(
        MemberCreateRequest(
            gym_id=gym_id,
            first_name="NoCustomer",
            last_name="NeedsOne",
            send_invite=False,
        ),
    )).member
    created.track_customer(created_member.stripe_customer_id)

    try:
        pm_id = await created.payment_method()
        before = await snapshot_billing_state(
            stripe_client,
            created_member.stripe_customer_id,
            connect_opts,
        )

        resp = await management_service.update_card(
            created_member.member_id,
            MembersBillingUpdateCardRequest(
                payment_method_id=pm_id,
            ),
        )

        assert resp.stripe_payment_method_id == pm_id
        assert resp.card_brand == "visa"

        customer = await stripe_client.client.v1.customers.retrieve_async(
            created_member.stripe_customer_id,
            options=connect_opts,
        )
        assert _default_pm_id(customer) == pm_id
        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, created_member.member_id)


async def test_unlink_payment(
    management_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    pm_id = await created.payment_method()
    created_member = (await management_service.create_member(
        MemberCreateRequest(
            gym_id=gym_id,
            first_name="Unlink",
            last_name="Card",
            payment_method_id=pm_id,
            send_invite=False,
        ),
    )).member
    created.track_customer(created_member.stripe_customer_id)

    try:
        before = await snapshot_billing_state(
            stripe_client,
            created_member.stripe_customer_id,
            connect_opts,
        )

        resp = await management_service.unlink_payment(
            created_member.member_id,
        )

        assert resp.stripe_payment_method_id is None
        assert resp.card_brand is None
        assert resp.card_last_four is None
        # stripe_customer_id should still be set
        assert resp.stripe_customer_id is not None

        # Stripe side: customer still exists but has no default
        # payment method, and nothing was billed.
        customer = await stripe_client.client.v1.customers.retrieve_async(
            created_member.stripe_customer_id,
            options=connect_opts,
        )
        assert _default_pm_id(customer) is None, (
            f"Customer {created_member.stripe_customer_id} still has a default "
            f"payment method after unlink"
        )
        await assert_no_unexpected_charges(
            stripe_client,
            before,
            connect_opts,
        )
    finally:
        await delete_member_data(db_pool, created_member.member_id)
