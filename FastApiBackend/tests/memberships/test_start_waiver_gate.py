"""Membership-start waiver gate — the ``requires_resign`` floor.

The gate (``MemberMembershipsStartValidation._check_waivers``) runs before any
Stripe call, so it is tested here against its query directly (Stripe-free apart
from the plan factory): for each ``(member, plan)`` the member must have signed
every waiver in the plan's ``waiver_ids`` at a version >= the re-sign floor (the
highest version with ``requires_resign`` true). Requires the legal-hardening
migration (the signing path writes the new columns).
"""

import json
import uuid

from sqlalchemy import text

from src.memberships import SQL_DIR
from src.shared.sql_loader import load_sql
from src.waivers.schema.waivers_schema import (
    WaiverCreateRequest,
    WaiverUpdateData,
    WaiverUpdateRequest,
)
from src.waivers.service.waivers_service import WaiversService


async def _gate_rows(db_pool, gym_id, member_id, plan_id):
    """Run the start-gate query; return the unsigned-required-waiver rows."""
    sql = load_sql(SQL_DIR / "member_memberships_start_waivers_check.sql")
    pairs = json.dumps([{"member_id": str(member_id), "plan_id": str(plan_id)}])
    async with db_pool.session() as session:
        result = await session.execute(
            text(sql), {"pairs": pairs, "gym_id": str(gym_id)}
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


async def _an_employee_id(db_pool, gym_id) -> uuid.UUID:
    async with db_pool.session() as session:
        result = await session.execute(
            text("SELECT employee_id FROM gym_employees WHERE gym_id = :g LIMIT 1"),
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
            text("UPDATE gym_waivers SET current_version_id = NULL WHERE waiver_id = :w"),
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


async def _sign_current(svc, db_pool, gym_id, member_id, waiver_id, operator_id):
    waiver = await svc.get_waiver(waiver_id, gym_id)
    await svc.sign_waiver(
        gym_id=gym_id,
        member_id=member_id,
        waiver_id=waiver_id,
        waiver_version_id=waiver.current_version.version_id,
        signer_name="Jane Doe",
        consent_acknowledged=True,
        ip_address="0.0.0.0",
        user_agent="test",
        operator_employee_id=operator_id,
    )


async def test_gate_floor_minor_vs_material(db_pool, gym_id, created):
    """Unsigned blocks; signing clears; a minor edit doesn't re-block; a
    material edit (over a signed version) re-blocks — the re-sign floor."""
    svc = WaiversService(db_pool)
    member = await created.member(gym_id)
    operator_id = await _an_employee_id(db_pool, gym_id)
    waiver = await svc.create_waiver(
        WaiverCreateRequest(gym_id=gym_id, name="Liability Gate", body="v1"),
    )
    plan = await created.plan(gym_id, plan_name="Gate Plan", price_cents=5000)
    try:
        await _set_plan_waivers(db_pool, plan.plan_id, [waiver.waiver_id])

        # Unsigned → blocked.
        rows = await _gate_rows(db_pool, gym_id, member.member_id, plan.plan_id)
        assert [str(r["waiver_id"]) for r in rows] == [str(waiver.waiver_id)]

        # Sign the current version → clears.
        await _sign_current(
            svc, db_pool, gym_id, member.member_id, waiver.waiver_id, operator_id,
        )
        assert await _gate_rows(
            db_pool, gym_id, member.member_id, plan.plan_id
        ) == []

        # Minor edit (requires_resign=False) forks a new version but the prior
        # signature still satisfies the floor → still cleared.
        await svc.update_waiver(
            WaiverUpdateRequest(
                waiver_id=waiver.waiver_id,
                gym_id=gym_id,
                data=WaiverUpdateData(body="v2 minor", requires_resign=False),
            ),
        )
        assert await _gate_rows(
            db_pool, gym_id, member.member_id, plan.plan_id
        ) == []

        # Sign the minor version, then a MATERIAL edit (requires_resign=True)
        # forks a version above the floor → re-blocks (must re-sign).
        await _sign_current(
            svc, db_pool, gym_id, member.member_id, waiver.waiver_id, operator_id,
        )
        await svc.update_waiver(
            WaiverUpdateRequest(
                waiver_id=waiver.waiver_id,
                gym_id=gym_id,
                data=WaiverUpdateData(body="v3 material", requires_resign=True),
            ),
        )
        rows = await _gate_rows(db_pool, gym_id, member.member_id, plan.plan_id)
        assert [str(r["waiver_id"]) for r in rows] == [str(waiver.waiver_id)]
    finally:
        await _delete_waiver_rows(db_pool, waiver.waiver_id)


async def test_gate_noop_when_plan_has_no_waivers(db_pool, gym_id, created):
    """A plan with empty waiver_ids never blocks (the common case today)."""
    member = await created.member(gym_id)
    plan = await created.plan(gym_id, plan_name="No-Waiver Plan", price_cents=5000)
    assert await _gate_rows(
        db_pool, gym_id, member.member_id, plan.plan_id
    ) == []
