"""Integration tests for link/unlink preview (dry-run) operations.

Every test asserts:

1. The ``members`` row is unchanged (``account_linked_to_id`` untouched).
2. Stripe state is unchanged (no new invoices, no subscription items
   added/removed, no charges).
3. The preview return value is a
   ``PaymentsInvoicePreviewResponse`` or ``None`` when the parent has
   no recurring subscription.
"""

from uuid import uuid4

import pytest
from sqlalchemy import text

from src.payments.schema.payments_invoice_schema import (
    PaymentsInvoicePreviewResponse,
)
from tests.helpers.cleanup import delete_member_data

# ── Helpers ─────────────────────────────────────────────────────────


async def _fetch_profile(db_pool, member_id):
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT account_linked_to_id, "
                "stripe_sub_id_month "
                "FROM members "
                "WHERE member_id = :id"
            ),
            {"id": str(member_id)},
        )
        return result.mappings().fetchone()


async def _retrieve_sub(stripe_client, connect_opts, sub_id):
    return await stripe_client.client.v1.subscriptions.retrieve_async(
        sub_id,
        options=connect_opts,
    )


# ── Link preview: happy path ────────────────────────────────────────


async def test_preview_link_bare_parent_returns_none(
    management_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Parent with no recurring sub has no invoice to preview."""
    parent = await created.member(gym_id, first_name="Parent", last_name="Bare")
    child = await created.member(gym_id, first_name="Child", last_name="Bare")

    try:
        preview = await management_service.preview_link_account(
            child.member_id,
            parent.member_id,
        )
        assert preview is None

        # Child profile unchanged — still has no link.
        row = await _fetch_profile(db_pool, child.member_id)
        assert row["account_linked_to_id"] is None
    finally:
        await delete_member_data(db_pool, child.member_id)
        await delete_member_data(db_pool, parent.member_id)


async def test_preview_link_with_paying_parent_no_mutation(
    management_service,
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """Preview on a linking op where the parent has an active recurring
    sub must return a preview AND leave CRM + Stripe untouched.
    """
    pm_id = await created.payment_method()
    parent = await created.member(
        gym_id,
        first_name="P",
        last_name="Pay",
        payment_method_id=pm_id,
    )
    plan = await created.plan(gym_id)
    child = await created.member(gym_id, first_name="C", last_name="Pay")

    try:
        # Parent starts a recurring plan so there's a subscription the
        # preview can describe.
        await memberships_service.start(
            member_id=parent.member_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
            idempotency_key=uuid4(),
        )

        parent_profile_before = await _fetch_profile(db_pool, parent.member_id)
        sub_id = parent_profile_before["stripe_sub_id_month"]
        assert sub_id is not None

        sub_before = await _retrieve_sub(stripe_client, connect_opts, sub_id)
        items_before = sorted(
            (item.id, item.price.id, item.quantity) for item in sub_before["items"].data
        )
        invoice_before = sub_before.latest_invoice

        preview = await management_service.preview_link_account(
            child.member_id,
            parent.member_id,
        )

        assert isinstance(preview, PaymentsInvoicePreviewResponse)
        assert preview.currency
        assert preview.total >= 0

        # CRM: child still unlinked, parent still has same sub id.
        child_row = await _fetch_profile(db_pool, child.member_id)
        assert child_row["account_linked_to_id"] is None

        parent_row = await _fetch_profile(db_pool, parent.member_id)
        assert parent_row["stripe_sub_id_month"] == sub_id

        # Stripe: sub items and latest_invoice unchanged.
        sub_after = await _retrieve_sub(stripe_client, connect_opts, sub_id)
        items_after = sorted(
            (item.id, item.price.id, item.quantity) for item in sub_after["items"].data
        )
        assert items_after == items_before, (
            "preview_link_account must not alter Stripe subscription items"
        )
        assert sub_after.latest_invoice == invoice_before, (
            "preview_link_account must not create a new invoice"
        )
    finally:
        await delete_member_data(db_pool, child.member_id)
        await delete_member_data(db_pool, parent.member_id)


# ── Link preview: validation ───────────────────────────────────────


async def test_preview_link_self_raises(
    management_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    member = await created.member(gym_id)

    try:
        with pytest.raises(ValueError, match="themselves"):
            await management_service.preview_link_account(
                member.member_id,
                member.member_id,
            )
    finally:
        await delete_member_data(db_pool, member.member_id)


async def test_preview_link_already_linked_raises(
    management_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    parent = await created.member(gym_id, first_name="P", last_name="Already")
    child = await created.member(gym_id, first_name="C", last_name="Already")

    try:
        await management_service.link_account(
            child.member_id,
            parent.member_id,
        )
        with pytest.raises(ValueError, match="already linked"):
            await management_service.preview_link_account(
                child.member_id,
                parent.member_id,
            )
    finally:
        await delete_member_data(db_pool, child.member_id)
        await delete_member_data(db_pool, parent.member_id)


async def test_preview_link_with_active_recurring_raises(
    management_service,
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    parent = await created.member(gym_id, first_name="P", last_name="PreviewRecur")
    pm_id = await created.payment_method()
    child = await created.member(
        gym_id,
        first_name="C",
        last_name="PreviewRecur",
        payment_method_id=pm_id,
    )
    plan = await created.plan(gym_id)

    try:
        await memberships_service.start(
            member_id=child.member_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
            idempotency_key=uuid4(),
        )

        with pytest.raises(ValueError, match="active recurring"):
            await management_service.preview_link_account(
                child.member_id,
                parent.member_id,
            )
    finally:
        await delete_member_data(db_pool, child.member_id)
        await delete_member_data(db_pool, parent.member_id)


# ── Unlink preview: happy path ─────────────────────────────────────


async def test_preview_unlink_bare_parent_returns_none(
    management_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    parent = await created.member(gym_id, first_name="P", last_name="UnlinkBare")
    child = await created.member(gym_id, first_name="C", last_name="UnlinkBare")

    try:
        await management_service.link_account(
            child.member_id,
            parent.member_id,
        )

        preview = await management_service.preview_unlink_account(
            child.member_id,
        )
        assert preview is None

        # Child still linked — preview did not mutate.
        row = await _fetch_profile(db_pool, child.member_id)
        assert row["account_linked_to_id"] is not None
        assert str(row["account_linked_to_id"]) == str(parent.member_id)
    finally:
        await delete_member_data(db_pool, child.member_id)
        await delete_member_data(db_pool, parent.member_id)


# ── Unlink preview: validation ─────────────────────────────────────


async def test_preview_unlink_not_linked_raises(
    management_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    member = await created.member(gym_id)

    try:
        with pytest.raises(ValueError, match="not linked"):
            await management_service.preview_unlink_account(member.member_id)
    finally:
        await delete_member_data(db_pool, member.member_id)
