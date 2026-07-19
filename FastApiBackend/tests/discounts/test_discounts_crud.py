"""Integration tests for DiscountsService — coupon-free preset CRUD.

Presets are now plain gym config split across two tables: the IDENTITY
(``gym_discounts``: name + type) and its versioned, immutable VALUE rows
(``gym_discount_values``: percent/dollar + lifetime). Create/update/delete never
touch Stripe (coupons are computed at sync and written back onto the applied-
discount row). Editing a value mints a NEW active version; archiving
(is_deleted = true) or editing a preset never reaches across to a member's
frozen applied-discount row (which is pinned to a specific ``value_id``).

Requires a migrated local DB (gym_discounts identity + gym_discount_values +
the member_membership_applied_discounts table). No Stripe account is needed.
"""

from datetime import date
from uuid import uuid4

import pytest
from schema.gym_discount import (
    DiscountDurationUnit,
    DiscountType,
)
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError

from src.discounts.schema.discounts_schema import (
    DiscountCreateRequest,
    DiscountUpdateIdentity,
    DiscountUpdateRequest,
    DiscountValue,
)
from src.memberships.service.memberships_discounts import (
    MemberMembershipsDiscounts,
)


async def _create_custom(discounts_service, gym_id, created, pct=10.0):
    """Mint a `custom` discount the way the membership start flow does.

    The public create rejects `custom` (one-shot inline values only), so the
    helper uses the real mint path and returns the minted discount_id.
    """
    [discount_id] = await discounts_service.mint_custom_discounts(
        gym_id,
        [DiscountValue(
            percentage_off=pct,
            duration_amount=1,
            duration_unit=DiscountDurationUnit.cycle,
        )],
    )
    created.track_discount(discount_id)
    return discount_id


async def _row(db_pool, discount_id):
    """Identity row joined to its current ACTIVE value version."""
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT d.discount_name, v.value_id, v.percentage_off, "
                "v.dollar_off, v.duration_amount, "
                "v.duration_unit, v.end_date, d.is_deleted "
                "FROM gym_discounts_unfiltered d "
                "JOIN gym_discount_values_unfiltered v "
                "  ON v.discount_id = d.discount_id AND v.is_active = true "
                "WHERE d.discount_id = :id"
            ),
            {"id": str(discount_id)},
        )
        return result.mappings().fetchone()


async def test_create_percentage_discount(discounts_service, db_pool, gym_id, created):
    """A percent preset is inserted as plain intent, no Stripe coupon."""
    resp = await discounts_service.create_discount(
        DiscountCreateRequest(
            gym_id=gym_id,
            discount_name="20% Off",
            discount_type=DiscountType.preset,
            value=DiscountValue(
                percentage_off=20.0,
            ),
        ),
    )
    created.track_discount(resp.discount_id)

    assert resp.discount_id is not None
    assert resp.discount_name == "20% Off"
    assert resp.value.percentage_off == 20.0
    assert resp.value.dollar_off is None
    assert resp.is_deleted is False

    row = await _row(db_pool, resp.discount_id)
    assert row["percentage_off"] == 20.0


async def test_create_dollar_one_cycle_discount(discounts_service, gym_id, created):
    """A 1-cycle dollar preset stores duration_amount=1, duration_unit=cycle and no end_date."""
    resp = await discounts_service.create_discount(
        DiscountCreateRequest(
            gym_id=gym_id,
            discount_name="$10 Off",
            discount_type=DiscountType.preset,
            value=DiscountValue(
                dollar_off=1000,
                duration_amount=1,
                duration_unit=DiscountDurationUnit.cycle,
            ),
        ),
    )
    created.track_discount(resp.discount_id)

    assert resp.value.dollar_off == 1000
    assert resp.value.percentage_off is None
    assert resp.value.duration_amount == 1
    assert resp.value.duration_unit == DiscountDurationUnit.cycle
    assert resp.value.end_date is None


async def test_create_ongoing_with_duration_span(discounts_service, gym_id, created):
    """A preset with a duration span stores the span, no end_date."""
    resp = await discounts_service.create_discount(
        DiscountCreateRequest(
            gym_id=gym_id,
            discount_name="3-month 15% Off",
            discount_type=DiscountType.preset,
            value=DiscountValue(
                percentage_off=15.0,
                duration_amount=3,
                duration_unit=DiscountDurationUnit.month,
            ),
        ),
    )
    created.track_discount(resp.discount_id)

    assert resp.value.duration_amount == 3
    assert resp.value.duration_unit == DiscountDurationUnit.month
    assert resp.value.end_date is None


async def test_create_rejects_span_and_end_date_together(discounts_service, gym_id):
    """The lifetime is a span XOR an explicit end_date — never both."""
    with pytest.raises(ValueError, match="never both"):
        DiscountValue(
            percentage_off=10.0,
            duration_amount=2,
            duration_unit=DiscountDurationUnit.month,
            end_date=date(2027, 1, 1),
        )


async def test_update_discount_edits_intent_only(discounts_service, db_pool, gym_id, created):
    """Update renames the identity and mints a new active value version.

    The previous version's ``is_active`` flips, so ``_row`` (which joins the
    active version) reflects the new value while older applied-discount rows
    stay pinned to their original ``value_id``. The request carries both an
    ``identity`` (rename) and a complete ``value`` (new version).
    """
    created_resp = await discounts_service.create_discount(
        DiscountCreateRequest(
            gym_id=gym_id,
            discount_name="Old Name",
            discount_type=DiscountType.preset,
            value=DiscountValue(
                percentage_off=15.0,
            ),
        ),
    )
    created.track_discount(created_resp.discount_id)

    resp = await discounts_service.update_discount(
        DiscountUpdateRequest(
            discount_id=created_resp.discount_id,
            gym_id=gym_id,
            identity=DiscountUpdateIdentity(discount_name="New Name"),
            value=DiscountValue(
                percentage_off=25.0,
            ),
        ),
    )

    assert resp.discount_id == created_resp.discount_id
    assert resp.discount_name == "New Name"
    assert resp.value.percentage_off == 25.0

    row = await _row(db_pool, created_resp.discount_id)
    assert row["discount_name"] == "New Name"
    assert row["percentage_off"] == 25.0


async def test_update_rename_only(discounts_service, db_pool, gym_id, created):
    """An identity-only update renames in place and mints NO new version.

    With ``value`` omitted, the active ``value_id`` must be untouched — the
    rename never reaches across to the versioned value rows.
    """
    created_resp = await discounts_service.create_discount(
        DiscountCreateRequest(
            gym_id=gym_id,
            discount_name="Before",
            discount_type=DiscountType.preset,
            value=DiscountValue(
                percentage_off=12.0,
            ),
        ),
    )
    created.track_discount(created_resp.discount_id)
    before = await _row(db_pool, created_resp.discount_id)

    resp = await discounts_service.update_discount(
        DiscountUpdateRequest(
            discount_id=created_resp.discount_id,
            gym_id=gym_id,
            identity=DiscountUpdateIdentity(discount_name="After"),
        ),
    )

    assert resp.discount_name == "After"
    assert resp.value.percentage_off == 12.0

    after = await _row(db_pool, created_resp.discount_id)
    assert after["discount_name"] == "After"
    assert after["value_id"] == before["value_id"], (
        "a rename-only update must not mint a new value version"
    )


async def test_update_value_only(discounts_service, db_pool, gym_id, created):
    """A value-only update mints a new version and preserves the name."""
    created_resp = await discounts_service.create_discount(
        DiscountCreateRequest(
            gym_id=gym_id,
            discount_name="Keep Name",
            discount_type=DiscountType.preset,
            value=DiscountValue(
                percentage_off=10.0,
            ),
        ),
    )
    created.track_discount(created_resp.discount_id)
    before = await _row(db_pool, created_resp.discount_id)

    resp = await discounts_service.update_discount(
        DiscountUpdateRequest(
            discount_id=created_resp.discount_id,
            gym_id=gym_id,
            value=DiscountValue(
                percentage_off=30.0,
            ),
        ),
    )

    assert resp.discount_name == "Keep Name"
    assert resp.value.percentage_off == 30.0

    after = await _row(db_pool, created_resp.discount_id)
    assert after["discount_name"] == "Keep Name"
    assert after["percentage_off"] == 30.0
    assert after["value_id"] != before["value_id"], "a value edit must mint a new active version"


async def test_update_requires_identity_or_value(gym_id):
    """The request must carry at least one of identity / value."""
    with pytest.raises(ValueError, match="at least one of identity or value"):
        DiscountUpdateRequest(
            discount_id=uuid4(),
            gym_id=gym_id,
        )


async def test_delete_discount_archives(discounts_service, db_pool, gym_id, created):
    """Delete is a soft archive (is_deleted = true); no Stripe call."""
    created_resp = await discounts_service.create_discount(
        DiscountCreateRequest(
            gym_id=gym_id,
            discount_name="Archive Me",
            discount_type=DiscountType.preset,
            value=DiscountValue(
                percentage_off=5.0,
            ),
        ),
    )
    created.track_discount(created_resp.discount_id)

    await discounts_service.delete_discount(created_resp.discount_id, gym_id)

    async with db_pool.session() as session:
        result = await session.execute(
            text("SELECT is_deleted FROM gym_discounts_unfiltered WHERE discount_id = :id"),
            {"id": str(created_resp.discount_id)},
        )
        row = result.mappings().fetchone()
    assert row["is_deleted"] is True


async def test_archive_leaves_applied_discounts_untouched(
    discounts_service, db_pool, gym_id, created
):
    """Archiving a preset does NOT delete a member's frozen applied-discount row.

    Predictability: editing/deleting a preset never reaches across to an
    existing member's applied-discount row — the holder keeps it. We stand up
    a membership + an applied-discount row pinned to the preset's active value
    version, then archive the preset and assert the row is intact.
    """
    created_resp = await discounts_service.create_discount(
        DiscountCreateRequest(
            gym_id=gym_id,
            discount_name="Held Discount",
            discount_type=DiscountType.preset,
            value=DiscountValue(
                percentage_off=10.0,
            ),
        ),
    )
    created.track_discount(created_resp.discount_id)

    member_id = None
    try:
        member_id, item_id, plan_id = await _seed_membership_with_applied_discount(
            db_pool,
            gym_id,
            value_id=created_resp.value_id,
        )
        created.track_plan_db(plan_id)

        await discounts_service.delete_discount(created_resp.discount_id, gym_id)

        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT count(*) AS n "
                    "FROM member_membership_applied_discounts_unfiltered "
                    "WHERE item_id = :item_id AND value_id = :value_id"
                ),
                {
                    "item_id": str(item_id),
                    "value_id": str(created_resp.value_id),
                },
            )
            n = result.mappings().fetchone()["n"]
        assert n == 1, "Archiving the preset must not remove the holder's applied-discount row"
    finally:
        if member_id is not None:
            await _delete_seeded_membership(db_pool, member_id)


# ── Local seed helpers (DB-only; no Stripe needed) ───────────────────


async def _seed_membership_with_applied_discount(db_pool, gym_id, value_id):
    """Insert a member + membership + one applied-discount row.

    The applied-discount row is pinned to ``value_id`` (the discount's active
    version) — the provenance/version tag in the new model. Returns
    (member, item, plan).
    """
    async with db_pool.session() as session:
        member_row = await session.execute(
            text(
                "INSERT INTO members (gym_id, first_name, last_name) "
                "VALUES (:gym_id, 'Snap', 'Holder') RETURNING member_id"
            ),
            {"gym_id": str(gym_id)},
        )
        member_id = member_row.mappings().fetchone()["member_id"]

        plan_row = await session.execute(
            text(
                "INSERT INTO membership_plans_unfiltered "
                "(gym_id, plan_name, image_url, plan_type, duration_amount, "
                " duration_unit, is_public, stripe_product_id) "
                "VALUES (:gym_id, 'Snap Plan', :img, 'recurring', 1, 'month', "
                " true, :sp) RETURNING plan_id"
            ),
            {
                "gym_id": str(gym_id),
                "img": (
                    "https://cdn.combatden.net/membership/presets/"
                    "activity-01.jpg"
                ),
                "sp": f"prod_{uuid4().hex[:16]}",
            },
        )
        plan_id = plan_row.mappings().fetchone()["plan_id"]

        price_row = await session.execute(
            text(
                "INSERT INTO membership_plan_prices_unfiltered "
                "(plan_id, gym_id, stripe_price_id, price, is_active) "
                "VALUES (:plan_id, :gym_id, :pr, 5000, true) RETURNING price_id"
            ),
            {
                "plan_id": str(plan_id),
                "gym_id": str(gym_id),
                "pr": f"price_{uuid4().hex[:16]}",
            },
        )
        price_id = price_row.mappings().fetchone()["price_id"]

        mem_row = await session.execute(
            text(
                "INSERT INTO member_memberships_unfiltered "
                "(member_id, paid_by_member_id, gym_id, plan_id, price_id, "
                " start_date, total_price, stripe_item_id) "
                "VALUES (:member_id, :member_id, :gym_id, :plan_id, :price_id, "
                " CURRENT_DATE, 5000, :si) RETURNING item_id"
            ),
            {
                "member_id": str(member_id),
                "gym_id": str(gym_id),
                "plan_id": str(plan_id),
                "price_id": str(price_id),
                "si": f"si_{uuid4().hex[:16]}",
            },
        )
        item_id = mem_row.mappings().fetchone()["item_id"]

        await session.execute(
            text(
                "INSERT INTO member_membership_applied_discounts_unfiltered "
                "(item_id, member_id, gym_id, value_id) "
                "VALUES (:item_id, :member_id, :gym_id, :value_id)"
            ),
            {
                "item_id": str(item_id),
                "member_id": str(member_id),
                "gym_id": str(gym_id),
                "value_id": str(value_id),
            },
        )
        await session.commit()
    return member_id, item_id, plan_id


async def _delete_seeded_membership(db_pool, member_id):
    async with db_pool.session() as session:
        await session.execute(
            text(
                "DELETE FROM member_membership_applied_discounts_unfiltered WHERE member_id = :id"
            ),
            {"id": str(member_id)},
        )
        await session.execute(
            text("DELETE FROM member_memberships_unfiltered WHERE member_id = :id"),
            {"id": str(member_id)},
        )
        await session.execute(
            text("DELETE FROM members WHERE member_id = :id"),
            {"id": str(member_id)},
        )
        await session.commit()


# ── Custom discounts are one-shot + single-owner ─────────────────────


async def test_create_rejects_custom_discount(discounts_service, gym_id):
    """The public create NEVER makes a `custom` discount.

    Customs are one-shot inline values minted only by the membership start
    flow (mint_custom_discounts) — a catalog entry of type `custom` is
    rejected at the service, so no API caller (CRM, seed) can create one.
    """
    with pytest.raises(ValueError, match="cannot be created directly"):
        await discounts_service.create_discount(
            DiscountCreateRequest(
                gym_id=gym_id,
                discount_name="Sneaky custom",
                discount_type=DiscountType.custom,
                value=DiscountValue(
                    percentage_off=10.0,
                    duration_amount=1,
                    duration_unit=DiscountDurationUnit.cycle,
                ),
            ),
        )



async def test_update_rejects_custom_discount(discounts_service, gym_id, created):
    """A custom discount is one-shot: any edit is rejected at the service.

    Customs are mint -> apply once -> archive; a rename or a new value
    version is never valid (the DB trigger enforces the value half too).
    """
    custom_id = await _create_custom(discounts_service, gym_id, created)

    with pytest.raises(ValueError, match="one-shot"):
        await discounts_service.update_discount(
            DiscountUpdateRequest(
                discount_id=custom_id,
                gym_id=gym_id,
                value=DiscountValue(
                    percentage_off=20.0,
                    duration_amount=1,
                    duration_unit=DiscountDurationUnit.cycle,
                ),
            ),
        )


async def test_apply_rejects_custom_outside_membership_flow(
    discounts_service, db_pool, gym_id, created
):
    """The public add path never applies a custom discount.

    Customs are minted by a membership flow (start/batch) and applied only by
    it (``allow_custom=True``). The default path — what the /discounts/add API
    reaches — rejects a custom id, so a minted custom can never be attached to
    another membership.
    """
    preset = await discounts_service.create_discount(
        DiscountCreateRequest(
            gym_id=gym_id,
            discount_name="Guard Preset",
            discount_type=DiscountType.preset,
            value=DiscountValue(
                percentage_off=5.0,
            ),
        ),
    )
    created.track_discount(preset.discount_id)
    custom_id = await _create_custom(discounts_service, gym_id, created)

    member_id = None
    try:
        member_id, item_id, plan_id = await _seed_membership_with_applied_discount(
            db_pool,
            gym_id,
            value_id=preset.value_id,
        )
        created.track_plan_db(plan_id)

        # add_applied_discounts is pure DB, so the unused payment-sync /
        # gym-stripe deps are stubbed with None for this guard test.
        service = MemberMembershipsDiscounts(db_pool, None, None)
        with pytest.raises(ValueError, match="single-use"):
            await service.add_applied_discounts(
                item_id=item_id,
                member_id=member_id,
                gym_id=gym_id,
                discount_ids=[custom_id],
                apply_date=date.today(),
            )
    finally:
        if member_id is not None:
            await _delete_seeded_membership(db_pool, member_id)


async def test_db_rejects_second_value_version_for_custom(
    discounts_service, db_pool, gym_id, created
):
    """DB trigger: a custom discount can never get a second value version.

    Requires migration 20260610120000_custom_discount_single_use.
    """
    custom_id = await _create_custom(discounts_service, gym_id, created)

    async with db_pool.session() as session:
        with pytest.raises(DBAPIError, match="one-shot"):
            await session.execute(
                text(
                    "INSERT INTO gym_discount_values_unfiltered "
                    "(discount_id, gym_id, percentage_off, is_active) "
                    "VALUES (:d, :g, 20.0, false)"
                ),
                {"d": str(custom_id), "g": str(gym_id)},
            )


async def test_db_rejects_second_application_for_custom(
    discounts_service, db_pool, gym_id, created
):
    """DB trigger: a custom discount's value applies to at most ONE membership.

    The first applied row (the membership flow's) inserts fine; any second row
    referencing the custom's value dies at the DB — the boundary that makes
    single-failure cleanup safe. Requires migration
    20260610120000_custom_discount_single_use.
    """
    custom_id = await _create_custom(discounts_service, gym_id, created)
    custom_value_id = (await _row(db_pool, custom_id))["value_id"]

    member_id = None
    try:
        member_id, item_id, plan_id = await _seed_membership_with_applied_discount(
            db_pool,
            gym_id,
            value_id=custom_value_id,  # first application — allowed
        )
        created.track_plan_db(plan_id)

        async with db_pool.session() as session:
            with pytest.raises(DBAPIError, match="single-use"):
                await session.execute(
                    text(
                        "INSERT INTO member_membership_applied_discounts_unfiltered "
                        "(item_id, member_id, gym_id, value_id) "
                        "VALUES (:item_id, :member_id, :gym_id, :value_id)"
                    ),
                    {
                        "item_id": str(item_id),
                        "member_id": str(member_id),
                        "gym_id": str(gym_id),
                        "value_id": str(custom_value_id),
                    },
                )
    finally:
        if member_id is not None:
            await _delete_seeded_membership(db_pool, member_id)
