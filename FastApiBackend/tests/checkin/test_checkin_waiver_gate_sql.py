"""The check-in waiver gate's query (``checkin_unsigned_waivers.sql``).

The gate requires every waiver across the member's CURRENT (active/frozen)
memberships' plans to be signed at a version >= the ``requires_resign`` floor
— the same set the member-detail Waivers section shows. Tested against the
query directly (Stripe-free apart from the plan factory; the membership row
is inserted direct-DB with a fake ``stripe_item_id`` so the status view
exposes it). Requires migrations ``20260702040000`` + ``20260702050000``.
"""

import json
import uuid

from sqlalchemy import text

from src.checkin import SQL_DIR
from src.shared.sql_loader import load_sql
from src.waivers.schema.waivers_schema import WaiverCreateRequest
from src.waivers.service.waivers_service import WaiversService


async def _unsigned_rows(db_pool, gym_id, member_id):
    sql = load_sql(SQL_DIR / "checkin_unsigned_waivers.sql")
    async with db_pool.session() as session:
        result = await session.execute(
            text(sql),
            {"member_id": str(member_id), "gym_id": str(gym_id)},
        )
        return result.mappings().fetchall()


async def _set_plan_waivers(db_pool, plan_id, waiver_ids) -> None:
    async with db_pool.session() as session:
        await session.execute(
            text(
                "UPDATE membership_plans SET waiver_ids = CAST(:w AS JSONB) "
                "WHERE plan_id = :p"
            ),
            {"w": json.dumps([str(w) for w in waiver_ids]), "p": str(plan_id)},
        )
        await session.commit()


async def _insert_active_membership(db_pool, gym_id, member_id, plan) -> uuid.UUID:
    """A live (view-visible) membership row: fake stripe ids, status added."""
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "INSERT INTO member_memberships_unfiltered ("
                "  member_id, paid_by_member_id, gym_id, plan_id, price_id, "
                "  start_date, stripe_item_id, total_price, stripe_sync_status"
                ") VALUES ("
                "  :member_id, :member_id, :gym_id, :plan_id, :price_id, "
                "  CURRENT_DATE - 7, :stripe_item_id, 5000, "
                "  CAST('applied' AS stripe_sync_status)"
                ") RETURNING item_id"
            ),
            {
                "member_id": str(member_id),
                "gym_id": str(gym_id),
                "plan_id": str(plan.plan_id),
                "price_id": str(plan.price_id),
                "stripe_item_id": f"si_test_{uuid.uuid4().hex[:16]}",
            },
        )
        item_id = result.mappings().one()["item_id"]
        await session.commit()
    return item_id


async def _delete_membership_row(db_pool, item_id) -> None:
    async with db_pool.session() as session:
        await session.execute(
            text(
                "DELETE FROM member_memberships_unfiltered "
                "WHERE item_id = :i"
            ),
            {"i": str(item_id)},
        )
        await session.commit()


async def _an_employee_id(db_pool, gym_id) -> uuid.UUID:
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT employee_id FROM gym_employees "
                "WHERE gym_id = :g LIMIT 1"
            ),
            {"g": str(gym_id)},
        )
        return result.scalar_one()


async def _delete_waiver_rows(db_pool, waiver_id) -> None:
    async with db_pool.session() as session:
        await session.execute(
            text("DELETE FROM member_waiver_signatures WHERE waiver_id = :w"),
            {"w": str(waiver_id)},
        )
        await session.execute(
            text(
                "UPDATE gym_waivers SET current_version_id = NULL "
                "WHERE waiver_id = :w"
            ),
            {"w": str(waiver_id)},
        )
        await session.execute(
            text("DELETE FROM gym_waiver_versions WHERE waiver_id = :w"),
            {"w": str(waiver_id)},
        )
        await session.execute(
            text("DELETE FROM gym_waivers WHERE waiver_id = :w"),
            {"w": str(waiver_id)},
        )
        await session.commit()


async def test_checkin_gate_unsigned_then_signed(db_pool, gym_id, created):
    """An active membership whose plan requires an unsigned waiver flags the
    member; signing the current version clears them."""
    svc = WaiversService(db_pool)
    member = await created.member(gym_id)
    operator_id = await _an_employee_id(db_pool, gym_id)
    waiver = await svc.create_waiver(
        WaiverCreateRequest(gym_id=gym_id, name="Checkin Gate", body="v1"),
    )
    plan = await created.plan(gym_id, plan_name="Checkin Gate Plan", price_cents=5000)
    item_id = None
    try:
        await _set_plan_waivers(db_pool, plan.plan_id, [waiver.waiver_id])

        # No membership yet → nothing required.
        assert await _unsigned_rows(db_pool, gym_id, member.member_id) == []

        item_id = await _insert_active_membership(
            db_pool, gym_id, member.member_id, plan
        )

        # Active membership + unsigned required waiver → flagged.
        rows = await _unsigned_rows(db_pool, gym_id, member.member_id)
        assert [str(r["waiver_id"]) for r in rows] == [str(waiver.waiver_id)]

        # Sign the current version → cleared.
        loaded = await svc.get_waiver(waiver.waiver_id, gym_id)
        await svc.sign_waiver(
            gym_id=gym_id,
            member_id=member.member_id,
            waiver_id=waiver.waiver_id,
            waiver_version_id=loaded.current_version.version_id,
            signer_name="Jane Doe",
            consent_acknowledged=True,
            ip_address="0.0.0.0",
            user_agent="test",
            operator_employee_id=operator_id,
        )
        assert await _unsigned_rows(db_pool, gym_id, member.member_id) == []
    finally:
        if item_id is not None:
            await _delete_membership_row(db_pool, item_id)
        await _delete_waiver_rows(db_pool, waiver.waiver_id)
