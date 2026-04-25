"""Mid-cycle remove-discount tests using Stripe Test Clocks.

Covers the two realistic paths for stripping a discount off an
active membership:

1. The gym deletes the discount entirely via the discounts service.
   This cascades through ``_remove_discount_from_memberships`` and
   queues ``bulk_payment_sync`` on a ``BackgroundTasks`` instance —
   the test runs the queued tasks inline so assertions can fire
   synchronously.
2. The gym detaches the discount from a specific active membership
   via the first-class ``PUT /member_memberships/discounts``
   endpoint (``memberships_service.update_discounts(discount_ids=[])``).
   The discount itself still exists in the gym's catalog.

Both paths must: (a) scrub the coupon off the Stripe subscription
item, (b) leave no mid-cycle invoice, (c) bill the next cycle at
the full undiscounted price.
"""

from datetime import datetime, timedelta
from uuid import UUID, uuid4

import pytest
from schema.gym_discount import DiscountType
from starlette.background import BackgroundTasks

from src.discounts.schema.discounts_schema import DiscountCreateRequest
from src.payments.schema.payments_enums import StripeCouponDuration
from tests.helpers.cleanup import delete_member_data
from tests.helpers.data_factory import (
    create_member,
    create_payment_method,
    create_plan,
)
from tests.helpers.db_reads import (
    get_active_membership_item_id,
    get_profile_stripe_ids,
)
from tests.helpers.stripe_assertions import (
    advance_to_next_cycle_and_fetch_invoice,
    assert_invoice_matches,
    assert_item_discounts,
    assert_no_unexpected_charges,
    fetch_subscription,
    snapshot_billing_state,
)
from tests.helpers.stripe_clock import (
    create_test_clock,
    delete_test_clock,
)

CLOCK_START = datetime(2026, 1, 15, 0, 0, 0)
NEXT_CYCLE = CLOCK_START + timedelta(days=35)


async def _start_membership_with_discount(
    memberships_service,
    member,
    gym_id,
    plan,
    discount_id: UUID,
) -> None:
    """Start a recurring membership carrying a single plan discount."""
    await memberships_service.start(
        crm_user_id=member.crm_user_id,
        gym_id=gym_id,
        plan_id=plan.plan_id,
        price_id=plan.price_id,
        idempotency_key=uuid4(),
        discount_ids=[discount_id],
    )


def _find_item_index_by_price(sub, stripe_price_id: str) -> int:
    for idx, item in enumerate(sub.items.data):
        if item.price.id == stripe_price_id:
            return idx
    raise AssertionError(
        f"No item on subscription {sub.id} uses price {stripe_price_id}; "
        f"items={[i.price.id for i in sub.items.data]}"
    )


# ── Tests ───────────────────────────────────────────────────────


@pytest.mark.timeout(240)
async def test_delete_discount_cascades_to_active_member_next_invoice_full_price(
    memberships_service,
    payment_sync_service,
    discounts_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    """Deleting a preset discount while a member is actively using it
    must scrub the coupon from their Stripe subscription item and
    bill the next cycle at the full price. The cascade runs via the
    ``DiscountsService.delete_discount`` background fan-out, which
    this test executes inline by invoking the BackgroundTasks stack.
    """
    clock_id = await create_test_clock(stripe_client, CLOCK_START, connect_opts)
    member = None
    discount = None
    try:
        pm_id = await create_payment_method(stripe_client, connect_opts)
        member = await create_member(
            db_pool,
            stripe_client,
            gym_id,
            connect_opts,
            payment_method_id=pm_id,
            test_clock_id=clock_id,
        )
        plan = await create_plan(
            db_pool,
            stripe_client,
            gym_id,
            connect_opts,
            price_cents=5000,
        )
        discount = await discounts_service.create_discount(
            DiscountCreateRequest(
                gym_id=gym_id,
                discount_name="Soon-to-be-deleted 25% Off",
                discount_type=DiscountType.preset,
                percentage_off=25.0,
                duration=StripeCouponDuration.forever,
            ),
        )

        await _start_membership_with_discount(
            memberships_service,
            member,
            gym_id,
            plan,
            discount.discount_id,
        )
        profile = await get_profile_stripe_ids(
            db_pool,
            member.crm_user_id,
            gym_id,
        )

        # First-pass guarantee: ``start(discount_ids=[...])`` must
        # attach the coupon to the Stripe item on its own sync,
        # without a second settle call. This is the real path
        # production callers use, and anything less means we are
        # shipping an undiscounted first invoice.
        sub = await fetch_subscription(
            stripe_client,
            profile.stripe_sub_id_month,
            connect_opts,
        )
        idx = _find_item_index_by_price(sub, plan.stripe_price_id)
        assert_item_discounts(sub, {discount.stripe_coupon_id}, index=idx)

        before = await snapshot_billing_state(
            stripe_client,
            profile.stripe_customer_id,
            connect_opts,
        )

        # Fire the delete. The service queues ``bulk_payment_sync``
        # on the BackgroundTasks instance — calling the object runs
        # every queued task in order, which is how Starlette executes
        # them in production after the response is sent.
        bg = BackgroundTasks()
        await discounts_service.delete_discount(
            discount.discount_id,
            gym_id,
            background_tasks=bg,
        )
        await bg()

        # Stripe side: coupon scrubbed and no extra invoice.
        sub = await fetch_subscription(
            stripe_client,
            profile.stripe_sub_id_month,
            connect_opts,
        )
        idx = _find_item_index_by_price(sub, plan.stripe_price_id)
        assert_item_discounts(sub, set(), index=idx)
        await assert_no_unexpected_charges(
            stripe_client,
            before,
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
        assert_invoice_matches(invoice, amount_due=5000)
    finally:
        if member is not None:
            await delete_member_data(db_pool, member.crm_user_id)
        await delete_test_clock(stripe_client, clock_id, connect_opts)


@pytest.mark.timeout(240)
async def test_remove_discount_from_sub_via_update_discounts_endpoint(
    memberships_service,
    discounts_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
):
    """First-class detach path: the discount is still registered in
    the gym, but we strip it off the active membership by calling
    ``update_discounts(discount_ids=[])``. The Stripe item must lose
    the coupon and the next invoice must bill the full price, even
    though the discount itself still exists.
    """
    clock_id = await create_test_clock(stripe_client, CLOCK_START, connect_opts)
    member = None
    try:
        pm_id = await create_payment_method(stripe_client, connect_opts)
        member = await create_member(
            db_pool,
            stripe_client,
            gym_id,
            connect_opts,
            payment_method_id=pm_id,
            test_clock_id=clock_id,
        )
        plan = await create_plan(
            db_pool,
            stripe_client,
            gym_id,
            connect_opts,
            price_cents=5000,
        )
        discount = await discounts_service.create_discount(
            DiscountCreateRequest(
                gym_id=gym_id,
                discount_name="Override Removable 30% Off",
                discount_type=DiscountType.preset,
                percentage_off=30.0,
                duration=StripeCouponDuration.forever,
            ),
        )

        await _start_membership_with_discount(
            memberships_service,
            member,
            gym_id,
            plan,
            discount.discount_id,
        )
        profile = await get_profile_stripe_ids(
            db_pool,
            member.crm_user_id,
            gym_id,
        )
        item_id = await get_active_membership_item_id(
            db_pool,
            member.crm_user_id,
            gym_id,
        )

        sub = await fetch_subscription(
            stripe_client,
            profile.stripe_sub_id_month,
            connect_opts,
        )
        idx = _find_item_index_by_price(sub, plan.stripe_price_id)
        assert_item_discounts(sub, {discount.stripe_coupon_id}, index=idx)

        before = await snapshot_billing_state(
            stripe_client,
            profile.stripe_customer_id,
            connect_opts,
        )

        await memberships_service.update_discounts(
            item_id=item_id,
            crm_user_id=member.crm_user_id,
            discount_ids=[],
            idempotency_key=uuid4(),
        )

        sub = await fetch_subscription(
            stripe_client,
            profile.stripe_sub_id_month,
            connect_opts,
        )
        idx = _find_item_index_by_price(sub, plan.stripe_price_id)
        assert_item_discounts(sub, set(), index=idx)
        await assert_no_unexpected_charges(
            stripe_client,
            before,
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
        assert_invoice_matches(invoice, amount_due=5000)
    finally:
        if member is not None:
            await delete_member_data(db_pool, member.crm_user_id)
        await delete_test_clock(stripe_client, clock_id, connect_opts)
