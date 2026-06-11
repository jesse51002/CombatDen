"""Integration tests for linked-account management (link / unlink).

Link / unlink are pure DB changes (no Stripe sync): they set / clear
``members.account_linked_to_id`` (and NULL the child's stripe/card fields) for a
member with zero active recurring memberships, so the family's consolidated
subscription is never touched. ``test_link_unlink_issues_no_charges`` is the
explicit guarantee of that.
"""

from uuid import uuid4

import pytest
from sqlalchemy import text

from src.members.schema.members_schema import MemberCreateRequest
from src.memberships.memberships_schema import (
    MemberMembershipsStartItem,
    MemberMembershipsStartRequest,
)
from tests.helpers.cleanup import delete_member_data

# ── Helpers ─────────────────────────────────────────────────────


async def _fetch_profile(db_pool, member_id):
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT account_linked_to_id, "
                "stripe_sub_id_month, stripe_payment_method_id, "
                "card_brand, card_last_four, card_exp_month, "
                "card_exp_year, freeze_start_date, freeze_end_date, "
                "payment_type "
                "FROM members "
                "WHERE member_id = :id"
            ),
            {"id": str(member_id)},
        )
        return result.mappings().fetchone()


async def _fetch_parent_sub_id(db_pool, member_id):
    async with db_pool.session() as session:
        result = await session.execute(
            text("SELECT stripe_sub_id_month FROM members WHERE member_id = :id"),
            {"id": str(member_id)},
        )
        row = result.mappings().fetchone()
    return row["stripe_sub_id_month"] if row else None


async def _retrieve_sub(stripe_client, connect_opts, sub_id):
    return await stripe_client.client.v1.subscriptions.retrieve_async(
        sub_id,
        options=connect_opts,
    )


# ── Link: happy path ────────────────────────────────────────────


async def test_link_happy_path(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    parent = await created.member(
        gym_id,
        first_name="Parent",
        last_name="One",
    )
    child = await created.member(
        gym_id,
        first_name="Child",
        last_name="One",
    )

    try:
        await memberships_service.link_account(
            child.member_id,
            parent.member_id,
        )

        row = await _fetch_profile(db_pool, child.member_id)
        assert row["account_linked_to_id"] is not None
        assert str(row["account_linked_to_id"]) == str(parent.member_id)
        # linked_account_no_stripe constraint fields must all be NULL
        assert row["stripe_sub_id_month"] is None
        assert row["card_brand"] is None
        assert row["card_last_four"] is None
        assert row["card_exp_month"] is None
        assert row["card_exp_year"] is None
        assert row["freeze_start_date"] is None
        assert row["freeze_end_date"] is None
        assert row["payment_type"] is None
    finally:
        await delete_member_data(db_pool, child.member_id)
        await delete_member_data(db_pool, parent.member_id)


async def test_link_clears_existing_card_fields(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """A child with an existing card should have card fields nulled on link."""
    parent = await created.member(
        gym_id,
        first_name="Parent",
        last_name="Card",
    )
    pm_id = await created.payment_method()
    child = await created.member(
        gym_id,
        first_name="Child",
        last_name="Card",
        payment_method_id=pm_id,
    )

    try:
        pre = await _fetch_profile(db_pool, child.member_id)
        assert pre["card_brand"] is not None  # sanity

        await memberships_service.link_account(
            child.member_id,
            parent.member_id,
        )

        row = await _fetch_profile(db_pool, child.member_id)
        assert str(row["account_linked_to_id"]) == str(parent.member_id)
        assert row["stripe_payment_method_id"] is None
        assert row["card_brand"] is None
        assert row["card_last_four"] is None
    finally:
        await delete_member_data(db_pool, child.member_id)
        await delete_member_data(db_pool, parent.member_id)


# ── Link: validation errors ─────────────────────────────────────


async def test_link_self_raises(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    member = await created.member(gym_id)

    try:
        with pytest.raises(ValueError, match="themselves"):
            await memberships_service.link_account(
                member.member_id,
                member.member_id,
            )
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_link_already_linked_raises(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    parent = await created.member(gym_id, first_name="P", last_name="A")
    child = await created.member(gym_id, first_name="C", last_name="A")

    try:
        await memberships_service.link_account(
            child.member_id,
            parent.member_id,
        )
        with pytest.raises(ValueError, match="already linked"):
            await memberships_service.link_account(
                child.member_id,
                parent.member_id,
            )
    finally:
        await delete_member_data(db_pool, child.member_id)
        await delete_member_data(db_pool, parent.member_id)


async def test_link_with_active_recurring_raises(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """A member with active recurring memberships cannot be linked."""
    parent = await created.member(gym_id, first_name="P", last_name="Recur")
    pm_id = await created.payment_method()
    child = await created.member(
        gym_id,
        first_name="C",
        last_name="Recur",
        payment_method_id=pm_id,
    )
    plan = await created.plan(gym_id)

    try:
        await memberships_service.start(
            MemberMembershipsStartRequest(
                payer_member_id=child.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=child.member_id,
                        price_id=plan.price_id,
                    ),
                ],
            )
        )

        with pytest.raises(ValueError, match="active recurring"):
            await memberships_service.link_account(
                child.member_id,
                parent.member_id,
            )

        # Child is unchanged
        row = await _fetch_profile(db_pool, child.member_id)
        assert row["account_linked_to_id"] is None
    finally:
        await delete_member_data(db_pool, child.member_id)
        await delete_member_data(db_pool, parent.member_id)


# ── Unlink: happy path ──────────────────────────────────────────


async def test_unlink_happy_path(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    parent = await created.member(gym_id, first_name="Parent", last_name="Unlink")
    child = await created.member(gym_id, first_name="Child", last_name="Unlink")

    try:
        await memberships_service.link_account(
            child.member_id,
            parent.member_id,
        )

        await memberships_service.unlink_account(
            child.member_id,
        )

        row = await _fetch_profile(db_pool, child.member_id)
        assert row["account_linked_to_id"] is None
    finally:
        await delete_member_data(db_pool, child.member_id)
        await delete_member_data(db_pool, parent.member_id)


# ── Unlink: validation errors ───────────────────────────────────


async def test_unlink_not_linked_raises(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    member = await created.member(gym_id)

    try:
        with pytest.raises(ValueError, match="not linked"):
            await memberships_service.unlink_account(
                member.member_id,
            )
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_unlink_with_active_recurring_raises(
    management_service,
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """A linked child with active recurring memberships cannot be unlinked."""
    pm_id = await created.payment_method()
    parent = await created.member(
        gym_id,
        first_name="P",
        last_name="UnlinkRecur",
        payment_method_id=pm_id,
    )
    child_req = MemberCreateRequest(
        gym_id=gym_id,
        first_name="C",
        last_name="UnlinkRecur",
    )
    child = await management_service.create_member(child_req)
    created.track_customer(child.stripe_customer_id)
    plan = await created.plan(gym_id)

    try:
        # Link via the supported flow — create_member never sets
        # account_linked_to_id (linking NULLs the child's own Stripe/card
        # fields). The linked child's membership then bills through the parent's
        # subscription.
        await memberships_service.link_account(child.member_id, parent.member_id)
        await memberships_service.start(
            MemberMembershipsStartRequest(
                payer_member_id=parent.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=child.member_id,
                        price_id=plan.price_id,
                    ),
                ],
            )
        )

        with pytest.raises(ValueError, match="active recurring"):
            await memberships_service.unlink_account(
                child.member_id,
            )

        # Child is still linked
        row = await _fetch_profile(db_pool, child.member_id)
        assert row["account_linked_to_id"] is not None
    finally:
        await delete_member_data(db_pool, child.member_id)
        await delete_member_data(db_pool, parent.member_id)


# ── No-charge guarantee (the explicit ask) ──────────────────────


async def test_link_unlink_issues_no_charges(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Link + unlink must not create new invoices or proration items on
    the parent's Stripe subscription. The parent has an active recurring
    plan; we capture the subscription state around each operation and confirm
    its invoice identity is unchanged. (Link / unlink are pure DB changes —
    they never call Stripe — so this holds by construction.)
    """
    pm_id = await created.payment_method()
    parent = await created.member(
        gym_id,
        first_name="P",
        last_name="NoCharge",
        payment_method_id=pm_id,
    )
    plan = await created.plan(gym_id)
    child = await created.member(gym_id, first_name="C", last_name="NoCharge")

    try:
        # Parent starts their own recurring membership — this creates
        # the Stripe subscription we'll be watching.
        await memberships_service.start(
            MemberMembershipsStartRequest(
                payer_member_id=parent.member_id,
                gym_id=gym_id,
                idempotency_key=uuid4(),
                memberships=[
                    MemberMembershipsStartItem(
                        member_id=parent.member_id,
                        price_id=plan.price_id,
                    ),
                ],
            )
        )

        sub_id = await _fetch_parent_sub_id(db_pool, parent.member_id)
        assert sub_id is not None

        sub_before = await _retrieve_sub(stripe_client, connect_opts, sub_id)
        items_before = sorted(
            (item.id, item.price.id, item.quantity) for item in sub_before["items"].data
        )
        invoice_before = sub_before.latest_invoice

        # ── Link the bare child ─────────────────────────────────
        await memberships_service.link_account(
            child.member_id,
            parent.member_id,
        )

        sub_after_link = await _retrieve_sub(
            stripe_client,
            connect_opts,
            sub_id,
        )
        items_after_link = sorted(
            (item.id, item.price.id, item.quantity) for item in sub_after_link["items"].data
        )
        assert items_after_link == items_before, (
            "link_account must not add or remove Stripe subscription items"
        )
        assert sub_after_link.latest_invoice == invoice_before, (
            "link_account must not create a new invoice"
        )

        # ── Unlink the child ─────────────────────────────────────
        await memberships_service.unlink_account(
            child.member_id,
        )

        sub_after_unlink = await _retrieve_sub(
            stripe_client,
            connect_opts,
            sub_id,
        )
        items_after_unlink = sorted(
            (item.id, item.price.id, item.quantity) for item in sub_after_unlink["items"].data
        )
        assert items_after_unlink == items_before, (
            "unlink_account must not add or remove Stripe subscription items"
        )
        assert sub_after_unlink.latest_invoice == invoice_before, (
            "unlink_account must not create a new invoice"
        )
    finally:
        await delete_member_data(db_pool, child.member_id)
        await delete_member_data(db_pool, parent.member_id)
