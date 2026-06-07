"""Discount preview staging (§2.5): a preview reflects the proposed change but
leaves NO permanent state.

``add_discounts(preview=True)`` stages a ``preview_add`` applied-discount row
(the preview build includes it), previews, then deletes it.
``remove_discounts(preview=True)`` flips the row to ``preview_remove`` (the build
drops it), previews, then reverts it to ``applied``. These verify the actual
insert-stage-cleanup / stamp-stage-revert machinery — not just the no-op
pass-through the parity test exercises.

No test clock: the recurring upcoming-invoice preview is the next full cycle.
"""

from uuid import uuid4

import pytest

from tests.helpers.cleanup import delete_member_data
from tests.helpers.db_reads import (
    get_active_membership_item_id,
    get_applied_snapshots,
)

PLAN_CENTS = 5000


async def _start_recurring(memberships_service, db_pool, member, gym_id, plan):
    await memberships_service.start(
        member_id=member.member_id,
        gym_id=gym_id,
        plan_id=plan.plan_id,
        price_id=plan.price_id,
        idempotency_key=uuid4(),
    )
    return await get_active_membership_item_id(db_pool, member.member_id, gym_id)


@pytest.mark.timeout(180)
async def test_add_discount_preview_reflects_then_stages_nothing(
    memberships_service,
    db_pool,
    gym_id,
    created,
):
    """add_discounts(preview=True) discounts the previewed bill, then leaves no
    applied-discount row (the staged preview_add is cleaned up)."""
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)
    plan = await created.plan(gym_id, price_cents=PLAN_CENTS)
    discount = await created.discount(
        gym_id,
        name="Preview Add 20% Off",
        percentage_off=20.0,
        discount_mode="ongoing",
    )
    try:
        item_id = await _start_recurring(
            memberships_service, db_pool, member, gym_id, plan
        )

        preview = await memberships_service.add_discounts(
            item_id=item_id,
            member_id=member.member_id,
            preset_ids=[discount.discount_id],
            idempotency_key=uuid4(),
            preview=True,
        )
        assert preview is not None
        # 5000 with 20% off ≈ 4000 — strictly less than full price.
        assert preview.amount_due < PLAN_CENTS

        # Nothing persisted: the preview_add row was staged then deleted.
        assert await get_applied_snapshots(db_pool, item_id) == []
    finally:
        await delete_member_data(db_pool, member.member_id)


@pytest.mark.timeout(180)
async def test_remove_discount_preview_reflects_then_reverts(
    memberships_service,
    db_pool,
    gym_id,
    created,
):
    """remove_discounts(preview=True) returns the previewed bill to full price,
    then leaves the applied-discount row intact (preview_remove reverted)."""
    pm_id = await created.payment_method()
    member = await created.member(gym_id, payment_method_id=pm_id)
    plan = await created.plan(gym_id, price_cents=PLAN_CENTS)
    discount = await created.discount(
        gym_id,
        name="Preview Remove 20% Off",
        percentage_off=20.0,
        discount_mode="ongoing",
    )
    try:
        item_id = await _start_recurring(
            memberships_service, db_pool, member, gym_id, plan
        )

        # Apply for real, then preview REMOVING it.
        await memberships_service.add_discounts(
            item_id=item_id,
            member_id=member.member_id,
            preset_ids=[discount.discount_id],
            idempotency_key=uuid4(),
        )
        snaps = await get_applied_snapshots(db_pool, item_id)
        assert len(snaps) == 1
        applied_id = snaps[0]["applied_discount_id"]

        preview = await memberships_service.remove_discounts(
            item_id=item_id,
            member_id=member.member_id,
            applied_ids=[applied_id],
            idempotency_key=uuid4(),
            preview=True,
        )
        assert preview is not None
        # Removing the 20% discount returns the bill to the full price.
        assert preview.amount_due == PLAN_CENTS

        # The row is still present and applied (the preview_remove was reverted).
        snaps_after = await get_applied_snapshots(db_pool, item_id)
        assert len(snaps_after) == 1
        assert snaps_after[0]["applied_discount_id"] == applied_id
    finally:
        await delete_member_data(db_pool, member.member_id)
