"""Preview-vs-actual-bill parity for link/unlink operations.

Each test runs ``preview_link_account`` (or ``preview_unlink_account``),
executes the real link/unlink, advances a Stripe Test Clock past the
parent's billing period, and asserts the preview totals equal the
renewal invoice totals.
"""

from datetime import datetime, timedelta
from uuid import uuid4

import pytest

from tests.helpers.cleanup import delete_member_data
from tests.helpers.data_factory import (
    create_member,
    create_payment_method,
    create_plan,
)
from tests.helpers.db_reads import get_profile_stripe_ids
from tests.helpers.preview_parity import assert_preview_matches_invoice
from tests.helpers.stripe_assertions import (
    advance_to_next_cycle_and_fetch_invoice,
    snapshot_billing_state,
)
from tests.helpers.stripe_clock import (
    create_test_clock,
    delete_test_clock,
)

CLOCK_START = datetime(2026, 1, 15, 0, 0, 0)
NEXT_CYCLE = CLOCK_START + timedelta(days=35)


@pytest.mark.timeout(180)
async def test_preview_link_matches_renewal(
    management_service,
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    """Linking a child to a paying parent: the preview returned for
    the parent must equal the parent's next renewal invoice.
    """
    clock_id = await create_test_clock(stripe_client, CLOCK_START, connect_opts)
    parent = None
    child = None
    try:
        pm_id = await create_payment_method(stripe_client, connect_opts)
        parent = await create_member(
            db_pool,
            stripe_client,
            gym_id,
            connect_opts,
            first_name="P",
            last_name="LinkParity",
            payment_method_id=pm_id,
            test_clock_id=clock_id,
        )
        child = await create_member(
            db_pool,
            stripe_client,
            gym_id,
            connect_opts,
            first_name="C",
            last_name="LinkParity",
            test_clock_id=clock_id,
        )
        plan = await create_plan(
            db_pool,
            stripe_client,
            gym_id,
            connect_opts,
            price_cents=5000,
        )
        await memberships_service.start(
            crm_user_id=parent.crm_user_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
            idempotency_key=uuid4(),
        )
        profile = await get_profile_stripe_ids(
            db_pool,
            parent.crm_user_id,
            gym_id,
        )
        assert profile.stripe_sub_id_month is not None

        preview = await management_service.preview_link_account(
            child.crm_user_id,
            parent.crm_user_id,
        )
        assert preview is not None

        await management_service.link_account(
            child.crm_user_id,
            parent.crm_user_id,
        )

        before = await snapshot_billing_state(
            stripe_client,
            profile.stripe_customer_id,
            connect_opts,
        )
        invoice = await advance_to_next_cycle_and_fetch_invoice(
            stripe_client,
            clock_id,
            NEXT_CYCLE,
            profile.stripe_sub_id_month,
            before,
            connect_opts,
        )
        assert_preview_matches_invoice(preview, invoice)
    finally:
        if child is not None:
            await delete_member_data(db_pool, child.crm_user_id)
        if parent is not None:
            await delete_member_data(db_pool, parent.crm_user_id)
        await delete_test_clock(stripe_client, clock_id, connect_opts)


@pytest.mark.timeout(180)
async def test_preview_unlink_matches_renewal(
    management_service,
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    """Unlinking a child from a paying parent: the preview must
    equal the parent's next renewal invoice after the unlink.
    """
    clock_id = await create_test_clock(stripe_client, CLOCK_START, connect_opts)
    parent = None
    child = None
    try:
        pm_id = await create_payment_method(stripe_client, connect_opts)
        parent = await create_member(
            db_pool,
            stripe_client,
            gym_id,
            connect_opts,
            first_name="P",
            last_name="UnlinkParity",
            payment_method_id=pm_id,
            test_clock_id=clock_id,
        )
        child = await create_member(
            db_pool,
            stripe_client,
            gym_id,
            connect_opts,
            first_name="C",
            last_name="UnlinkParity",
            test_clock_id=clock_id,
        )
        plan = await create_plan(
            db_pool,
            stripe_client,
            gym_id,
            connect_opts,
            price_cents=5000,
        )
        await memberships_service.start(
            crm_user_id=parent.crm_user_id,
            gym_id=gym_id,
            plan_id=plan.plan_id,
            price_id=plan.price_id,
            idempotency_key=uuid4(),
        )
        await management_service.link_account(
            child.crm_user_id,
            parent.crm_user_id,
        )
        profile = await get_profile_stripe_ids(
            db_pool,
            parent.crm_user_id,
            gym_id,
        )

        preview = await management_service.preview_unlink_account(
            child.crm_user_id,
        )
        assert preview is not None

        await management_service.unlink_account(child.crm_user_id)

        before = await snapshot_billing_state(
            stripe_client,
            profile.stripe_customer_id,
            connect_opts,
        )
        invoice = await advance_to_next_cycle_and_fetch_invoice(
            stripe_client,
            clock_id,
            NEXT_CYCLE,
            profile.stripe_sub_id_month,
            before,
            connect_opts,
        )
        assert_preview_matches_invoice(preview, invoice)
    finally:
        if child is not None:
            await delete_member_data(db_pool, child.crm_user_id)
        if parent is not None:
            await delete_member_data(db_pool, parent.crm_user_id)
        await delete_test_clock(stripe_client, clock_id, connect_opts)
