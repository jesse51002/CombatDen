"""Write-time integrity guard for ``membership_plans.waiver_ids``.

``waiver_ids`` is JSONB with no FK, so plan create/update validate the ids
via ``MembershipPlansBase._validate_waiver_ids``: every id must exist in the
gym, be non-archived, and be a ``custom`` waiver — special-purpose waivers
(the payer-auth agreement) are never plan-attachable. Exercised directly on
the guard (Stripe-free; the create/update paths call the same method).

Requires migration ``20260702050000`` (the ``waiver_type`` enum).
"""

from uuid import UUID, uuid4

import pytest
from sqlalchemy import text

from src.plans.service.plans_base import MembershipPlansBase
from src.waivers.schema.waivers_schema import WaiverCreateRequest
from src.waivers.service.waivers_service import WaiversService


def _guard(db_pool) -> MembershipPlansBase:
    """The guard only touches the DB pool — no Stripe deps needed."""
    return MembershipPlansBase(db_pool, None, None, None)


async def _payer_auth_waiver_id(db_pool, gym_id) -> UUID:
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT waiver_id FROM gym_waivers "
                "WHERE gym_id = :g AND waiver_type = 'payer_auth'",
            ),
            {"g": str(gym_id)},
        )
        return result.scalar_one()


async def _delete_waiver_rows(db_pool, waiver_id) -> None:
    async with db_pool.session() as session:
        await session.execute(
            text(
                "UPDATE gym_waivers SET current_version_id = NULL "
                "WHERE waiver_id = :w",
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


async def test_guard_accepts_custom_waiver(db_pool, gym_id):
    svc = WaiversService(db_pool)
    waiver = await svc.create_waiver(
        WaiverCreateRequest(gym_id=gym_id, name="Guard OK", body="# body"),
    )
    try:
        await _guard(db_pool)._validate_waiver_ids(
            gym_id, [waiver.waiver_id],
        )
    finally:
        await _delete_waiver_rows(db_pool, waiver.waiver_id)


async def test_guard_rejects_unknown_waiver(db_pool, gym_id):
    with pytest.raises(ValueError, match="not found"):
        await _guard(db_pool)._validate_waiver_ids(gym_id, [uuid4()])


async def test_guard_rejects_payer_auth_waiver(db_pool, gym_id):
    payer_auth_id = await _payer_auth_waiver_id(db_pool, gym_id)
    with pytest.raises(ValueError, match="Special-purpose"):
        await _guard(db_pool)._validate_waiver_ids(gym_id, [payer_auth_id])


async def test_guard_rejects_archived_waiver(db_pool, gym_id):
    svc = WaiversService(db_pool)
    waiver = await svc.create_waiver(
        WaiverCreateRequest(gym_id=gym_id, name="Guard Gone", body="# body"),
    )
    try:
        await svc.delete_waiver(waiver.waiver_id, gym_id)
        with pytest.raises(ValueError, match="Archived"):
            await _guard(db_pool)._validate_waiver_ids(
                gym_id, [waiver.waiver_id],
            )
    finally:
        await _delete_waiver_rows(db_pool, waiver.waiver_id)
