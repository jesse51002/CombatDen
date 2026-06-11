"""Regression: the CRM member billing-detail read path surfaces a
membership's applied discounts via the applied-discount model.

Guards the bug where ``member_details.sql`` still selected the removed
``member_memberships.discount_ids`` column, 500ing
``GET /members/{id}/billing`` for every member with
``UndefinedColumnError: column ms.discount_ids does not exist``. The read
path now aggregates each membership's currently-active applied-discount rows
(filtered view, joined to the pinned value version) into the membership card.

Requires a migrated local DB (the member_membership_applied_discounts table)
and the shared Stripe test account.
"""

from datetime import datetime
from uuid import uuid4

import pytest

from src.classes.service.classes_cycle_counts_service import (
    ClassesCycleCountsService,
)
from src.classes.service.classes_streak_service import ClassesStreakService
from src.members.service.member_details.members_billing_detail_service import (
    MembersBillingDetailService,
)
from src.memberships.memberships_schema import (
    MemberMembershipsStartItem,
    MemberMembershipsStartRequest,
)
from tests.helpers.cleanup import delete_member_data
from tests.helpers.db_reads import (
    get_active_membership_item_id,
    get_profile_stripe_ids,
)
from tests.helpers.stripe_clock import create_test_clock, delete_test_clock

CLOCK_START = datetime(2026, 1, 15, 0, 0, 0)


async def _start_membership(memberships_service, member, gym_id, plan):
    """Start a recurring membership with no discounts attached."""
    await memberships_service.start(
        MemberMembershipsStartRequest(
            payer_member_id=member.member_id,
            gym_id=gym_id,
            idempotency_key=uuid4(),
            memberships=[
                MemberMembershipsStartItem(
                    member_id=member.member_id,
                    price_id=plan.price_id,
                ),
            ],
        )
    )


@pytest.mark.timeout(180)
async def test_billing_detail_surfaces_active_applied_discount(
    memberships_service,
    db_pool,
    gym_id,
    stripe_client,
    connect_opts,
    created,
):
    """After applying an ongoing percent discount, the billing-detail read
    path returns 200-equivalent (no exception) and the discount appears on
    the membership card resolved to its pinned value version.
    """
    clock_id = await create_test_clock(stripe_client, CLOCK_START, connect_opts)
    member = None
    try:
        pm_id = await created.payment_method()
        member = await created.member(
            gym_id,
            payment_method_id=pm_id,
            test_clock_id=clock_id,
        )
        plan = await created.plan(gym_id, price_cents=5000)
        discount = await created.discount(
            gym_id,
            name="Billing-detail 10% Off",
            percentage_off=10.0,
            discount_mode="ongoing",
        )

        await _start_membership(memberships_service, member, gym_id, plan)
        item_id = await get_active_membership_item_id(
            db_pool, member.member_id, gym_id
        )
        # Sanity: the membership actually got a Stripe subscription, so the
        # apply below will sync and write back a coupon (making the applied-
        # discount row visible through the filtered applied-discounts view).
        profile = await get_profile_stripe_ids(db_pool, member.member_id, gym_id)
        assert profile.stripe_sub_id_month is not None

        await memberships_service.add_discounts(
            item_id=item_id,
            member_id=member.member_id,
            discount_ids=[discount.discount_id],
            idempotency_key=uuid4(),
        )

        # The read path that used to 500 on the dead discount_ids column.
        service = MembersBillingDetailService(
            db_pool,
            ClassesStreakService(db_pool),
            ClassesCycleCountsService(db_pool),
        )
        detail = await service.get_member_billing_detail(member.member_id)

        card = next(
            (m for m in detail.memberships if m.plan_id == plan.plan_id),
            None,
        )
        assert card is not None, "membership card for the started plan is missing"

        applied = [
            d for d in card.discounts if d.discount_id == discount.discount_id
        ]
        assert len(applied) == 1, (
            f"applied discount should surface once on the card, "
            f"got {card.discounts}"
        )
        info = applied[0]
        assert info.percentage_off == 10.0
        assert info.dollar_off is None
        assert info.discount_mode == "ongoing"
        # The rich applied-discount fields the CRM needs to group + remove the
        # discount must be populated (item-scoped, removable by id).
        assert info.item_id == item_id
        assert info.member_id == member.member_id
        assert info.applied_discount_id is not None
        assert info.value_id is not None
        # Ongoing forever (no duration / explicit end_date) -> applied-discount
        # row's end_date is NULL and the currently-active filter keeps it.
        assert info.end_date is None
    finally:
        if member is not None:
            await delete_member_data(db_pool, member.member_id)
        await delete_test_clock(stripe_client, clock_id, connect_opts)
