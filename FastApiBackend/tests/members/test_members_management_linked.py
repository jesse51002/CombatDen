"""Integration tests for linked-account management."""

import pytest
from sqlalchemy import text

from src.members.schema.members_management_schema import (
    MembersManagementCreateRequest,
)

from tests.helpers.cleanup import delete_member_data
from tests.helpers.data_factory import (
    create_member,
    create_payment_method,
    create_plan,
)


# ── Helpers ─────────────────────────────────────────────────────


async def _fetch_profile(db_pool, crm_user_id):
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT account_linked_to_id, linked_discount_id, "
                "stripe_sub_id_month, stripe_payment_method_id, "
                "card_brand, card_last_four, card_exp_month, "
                "card_exp_year, freeze_start_date, freeze_end_date, "
                "payment_type "
                "FROM user_gym_profiles_unfiltered "
                "WHERE crm_user_id = :id"
            ),
            {"id": str(crm_user_id)},
        )
        return result.mappings().fetchone()


async def _fetch_parent_sub_id(db_pool, crm_user_id):
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT stripe_sub_id_month "
                "FROM user_gym_profiles_unfiltered "
                "WHERE crm_user_id = :id"
            ),
            {"id": str(crm_user_id)},
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
    management_service, db_pool, gym_id,
    stripe_client, connect_opts,
):
    parent = await create_member(
        db_pool, stripe_client, gym_id, connect_opts,
        first_name="Parent", last_name="One",
    )
    child = await create_member(
        db_pool, stripe_client, gym_id, connect_opts,
        first_name="Child", last_name="One",
    )

    try:
        resp = await management_service.link_account(
            child.crm_user_id,
            parent.crm_user_id,
        )

        assert resp.account_linked_to_id == parent.crm_user_id

        row = await _fetch_profile(db_pool, child.crm_user_id)
        assert row["account_linked_to_id"] is not None
        assert str(row["account_linked_to_id"]) == str(parent.crm_user_id)
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
        await delete_member_data(db_pool, child.crm_user_id)
        await delete_member_data(db_pool, parent.crm_user_id)


async def test_link_clears_existing_card_fields(
    management_service, db_pool, gym_id,
    stripe_client, connect_opts,
):
    """A child with an existing card should have card fields nulled on link."""
    parent = await create_member(
        db_pool, stripe_client, gym_id, connect_opts,
        first_name="Parent", last_name="Card",
    )
    pm_id = await create_payment_method(stripe_client, connect_opts)
    child = await create_member(
        db_pool, stripe_client, gym_id, connect_opts,
        first_name="Child", last_name="Card",
        payment_method_id=pm_id,
    )

    try:
        pre = await _fetch_profile(db_pool, child.crm_user_id)
        assert pre["card_brand"] is not None  # sanity

        await management_service.link_account(
            child.crm_user_id,
            parent.crm_user_id,
        )

        row = await _fetch_profile(db_pool, child.crm_user_id)
        assert str(row["account_linked_to_id"]) == str(parent.crm_user_id)
        assert row["stripe_payment_method_id"] is None
        assert row["card_brand"] is None
        assert row["card_last_four"] is None
    finally:
        await delete_member_data(db_pool, child.crm_user_id)
        await delete_member_data(db_pool, parent.crm_user_id)


# ── Link: validation errors ─────────────────────────────────────


async def test_link_self_raises(
    management_service, db_pool, gym_id,
    stripe_client, connect_opts,
):
    member = await create_member(
        db_pool, stripe_client, gym_id, connect_opts,
    )

    try:
        with pytest.raises(ValueError, match="themselves"):
            await management_service.link_account(
                member.crm_user_id,
                member.crm_user_id,
            )
    finally:
        await delete_member_data(db_pool, member.crm_user_id)


async def test_link_already_linked_raises(
    management_service, db_pool, gym_id,
    stripe_client, connect_opts,
):
    parent = await create_member(
        db_pool, stripe_client, gym_id, connect_opts,
        first_name="P", last_name="A",
    )
    child = await create_member(
        db_pool, stripe_client, gym_id, connect_opts,
        first_name="C", last_name="A",
    )

    try:
        await management_service.link_account(
            child.crm_user_id, parent.crm_user_id,
        )
        with pytest.raises(ValueError, match="already linked"):
            await management_service.link_account(
                child.crm_user_id, parent.crm_user_id,
            )
    finally:
        await delete_member_data(db_pool, child.crm_user_id)
        await delete_member_data(db_pool, parent.crm_user_id)


async def test_link_with_active_recurring_raises(
    management_service, memberships_service, db_pool, gym_id,
    stripe_client, connect_opts,
):
    """A member with active recurring memberships cannot be linked."""
    parent = await create_member(
        db_pool, stripe_client, gym_id, connect_opts,
        first_name="P", last_name="Recur",
    )
    pm_id = await create_payment_method(stripe_client, connect_opts)
    child = await create_member(
        db_pool, stripe_client, gym_id, connect_opts,
        first_name="C", last_name="Recur",
        payment_method_id=pm_id,
    )
    plan = await create_plan(db_pool, stripe_client, gym_id, connect_opts)

    try:
        await memberships_service.start(
            crm_user_id=child.crm_user_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
        )

        with pytest.raises(ValueError, match="active recurring"):
            await management_service.link_account(
                child.crm_user_id, parent.crm_user_id,
            )

        # Child is unchanged
        row = await _fetch_profile(db_pool, child.crm_user_id)
        assert row["account_linked_to_id"] is None
    finally:
        await delete_member_data(db_pool, child.crm_user_id)
        await delete_member_data(db_pool, parent.crm_user_id)


# ── Unlink: happy path ──────────────────────────────────────────


async def test_unlink_happy_path(
    management_service, db_pool, gym_id,
    stripe_client, connect_opts,
):
    parent = await create_member(
        db_pool, stripe_client, gym_id, connect_opts,
        first_name="Parent", last_name="Unlink",
    )
    child = await create_member(
        db_pool, stripe_client, gym_id, connect_opts,
        first_name="Child", last_name="Unlink",
    )

    try:
        await management_service.link_account(
            child.crm_user_id, parent.crm_user_id,
        )

        resp = await management_service.unlink_account(child.crm_user_id)
        assert resp.account_linked_to_id is None

        row = await _fetch_profile(db_pool, child.crm_user_id)
        assert row["account_linked_to_id"] is None
        assert row["linked_discount_id"] is None
    finally:
        await delete_member_data(db_pool, child.crm_user_id)
        await delete_member_data(db_pool, parent.crm_user_id)


# ── Unlink: validation errors ───────────────────────────────────


async def test_unlink_not_linked_raises(
    management_service, db_pool, gym_id,
    stripe_client, connect_opts,
):
    member = await create_member(
        db_pool, stripe_client, gym_id, connect_opts,
    )

    try:
        with pytest.raises(ValueError, match="not linked"):
            await management_service.unlink_account(member.crm_user_id)
    finally:
        await delete_member_data(db_pool, member.crm_user_id)


async def test_unlink_with_active_recurring_raises(
    management_service, memberships_service, db_pool, gym_id,
    stripe_client, connect_opts,
):
    """A linked child with active recurring memberships cannot be unlinked."""
    pm_id = await create_payment_method(stripe_client, connect_opts)
    parent = await create_member(
        db_pool, stripe_client, gym_id, connect_opts,
        first_name="P", last_name="UnlinkRecur",
        payment_method_id=pm_id,
    )
    # Create child already linked to parent — linked accounts can
    # still have memberships (billed through parent's sub).
    child_req = MembersManagementCreateRequest(
        gym_id=gym_id,
        first_name="C",
        last_name="UnlinkRecur",
        account_linked_to_id=parent.crm_user_id,
    )
    child = await management_service.create_member(child_req)
    plan = await create_plan(db_pool, stripe_client, gym_id, connect_opts)

    try:
        await memberships_service.start(
            crm_user_id=child.crm_user_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
        )

        with pytest.raises(ValueError, match="active recurring"):
            await management_service.unlink_account(child.crm_user_id)

        # Child is still linked
        row = await _fetch_profile(db_pool, child.crm_user_id)
        assert row["account_linked_to_id"] is not None
    finally:
        await delete_member_data(db_pool, child.crm_user_id)
        await delete_member_data(db_pool, parent.crm_user_id)


# ── No-charge guarantee (the explicit ask) ──────────────────────


async def test_link_unlink_issues_no_charges(
    management_service, memberships_service, db_pool, gym_id,
    stripe_client, connect_opts,
):
    """Link + unlink must not create new invoices or proration items on
    the parent's Stripe subscription. The parent has an active recurring
    plan; we snapshot the subscription around each operation and confirm
    its invoice identity is unchanged.
    """
    pm_id = await create_payment_method(stripe_client, connect_opts)
    parent = await create_member(
        db_pool, stripe_client, gym_id, connect_opts,
        first_name="P", last_name="NoCharge",
        payment_method_id=pm_id,
    )
    plan = await create_plan(db_pool, stripe_client, gym_id, connect_opts)
    child = await create_member(
        db_pool, stripe_client, gym_id, connect_opts,
        first_name="C", last_name="NoCharge",
    )

    try:
        # Parent starts their own recurring membership — this creates
        # the Stripe subscription we'll be watching.
        await memberships_service.start(
            crm_user_id=parent.crm_user_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
        )

        sub_id = await _fetch_parent_sub_id(db_pool, parent.crm_user_id)
        assert sub_id is not None

        sub_before = await _retrieve_sub(stripe_client, connect_opts, sub_id)
        items_before = sorted(
            (item.id, item.price.id, item.quantity)
            for item in sub_before["items"].data
        )
        invoice_before = sub_before.latest_invoice

        # ── Link the bare child ─────────────────────────────────
        await management_service.link_account(
            child.crm_user_id,
            parent.crm_user_id,
        )

        sub_after_link = await _retrieve_sub(
            stripe_client, connect_opts, sub_id,
        )
        items_after_link = sorted(
            (item.id, item.price.id, item.quantity)
            for item in sub_after_link["items"].data
        )
        assert items_after_link == items_before, (
            "link_account must not add or remove Stripe subscription items"
        )
        assert sub_after_link.latest_invoice == invoice_before, (
            "link_account must not create a new invoice"
        )

        # ── Unlink the child ─────────────────────────────────────
        await management_service.unlink_account(child.crm_user_id)

        sub_after_unlink = await _retrieve_sub(
            stripe_client, connect_opts, sub_id,
        )
        items_after_unlink = sorted(
            (item.id, item.price.id, item.quantity)
            for item in sub_after_unlink["items"].data
        )
        assert items_after_unlink == items_before, (
            "unlink_account must not add or remove Stripe subscription items"
        )
        assert sub_after_unlink.latest_invoice == invoice_before, (
            "unlink_account must not create a new invoice"
        )
    finally:
        await delete_member_data(db_pool, child.crm_user_id)
        await delete_member_data(db_pool, parent.crm_user_id)
