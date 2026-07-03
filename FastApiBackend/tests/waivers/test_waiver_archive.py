"""Waiver archive semantics.

The payer-auth waiver is never archivable through the API path (the DB
trigger only blocks client roles — the backend runs at service role, so the
service-level guard is the real protection), and archiving a custom waiver
strips its id from every plan's ``waiver_ids`` in the same transaction.

Requires migrations ``20260702040000`` (legal hardening) and
``20260702050000`` (the ``waiver_type`` enum).
"""

import json
import uuid

import pytest
from sqlalchemy import text

from src.waivers.schema.waivers_schema import WaiverCreateRequest
from src.waivers.service.waivers_service import WaiversService


async def _payer_auth_waiver_id(db_pool, gym_id) -> str:
    async with db_pool.session() as session:
        result = await session.execute(
            text(
                "SELECT waiver_id FROM gym_waivers "
                "WHERE gym_id = :g AND waiver_type = 'payer_auth'",
            ),
            {"g": str(gym_id)},
        )
        return str(result.scalar_one())


async def _delete_waiver_rows(db_pool, waiver_id) -> None:
    """Remove a waiver + its versions (FK-safe order)."""
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


async def _delete_plan_row(db_pool, plan_id) -> None:
    async with db_pool.session() as session:
        await session.execute(
            text(
                "DELETE FROM membership_plans_unfiltered "
                "WHERE plan_id = :p",
            ),
            {"p": str(plan_id)},
        )
        await session.commit()


async def test_archive_payer_auth_waiver_rejected(db_pool, gym_id):
    """The payer-auth waiver cannot be archived via the service."""
    svc = WaiversService(db_pool)
    payer_auth_id = await _payer_auth_waiver_id(db_pool, gym_id)

    with pytest.raises(ValueError, match="cannot be archived"):
        await svc.delete_waiver(uuid.UUID(payer_auth_id), gym_id)

    # Still live.
    async with db_pool.session() as session:
        result = await session.execute(
            text("SELECT is_deleted FROM gym_waivers WHERE waiver_id = :w"),
            {"w": payer_auth_id},
        )
        assert result.scalar_one() is False


async def test_archive_strips_waiver_id_from_plans(db_pool, gym_id):
    """Archiving a custom waiver removes its id from plans' waiver_ids."""
    svc = WaiversService(db_pool)
    doomed = await svc.create_waiver(
        WaiverCreateRequest(gym_id=gym_id, name="Doomed", body="# doomed"),
    )
    keeper = await svc.create_waiver(
        WaiverCreateRequest(gym_id=gym_id, name="Keeper", body="# keeper"),
    )
    plan_id = None
    try:
        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "INSERT INTO membership_plans_unfiltered "
                    "(gym_id, plan_name, plan_type, class_count, "
                    " stripe_product_id, waiver_ids) "
                    "VALUES (:g, :n, 'one_time', 5, :sp, "
                    " CAST(:w AS JSONB)) "
                    "RETURNING plan_id",
                ),
                {
                    "g": str(gym_id),
                    "n": f"Strip Test {uuid.uuid4().hex[:8]}",
                    "sp": f"prod_test_{uuid.uuid4().hex[:12]}",
                    "w": json.dumps(
                        [str(doomed.waiver_id), str(keeper.waiver_id)],
                    ),
                },
            )
            plan_id = str(result.scalar_one())
            await session.commit()

        await svc.delete_waiver(doomed.waiver_id, gym_id)

        async with db_pool.session() as session:
            result = await session.execute(
                text(
                    "SELECT waiver_ids FROM membership_plans_unfiltered "
                    "WHERE plan_id = :p",
                ),
                {"p": plan_id},
            )
            remaining = result.scalar_one()
        assert remaining == [str(keeper.waiver_id)]
    finally:
        if plan_id is not None:
            await _delete_plan_row(db_pool, plan_id)
        await _delete_waiver_rows(db_pool, doomed.waiver_id)
        await _delete_waiver_rows(db_pool, keeper.waiver_id)
