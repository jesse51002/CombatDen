"""Conditional waiver-version immutability.

A 0-signature version is edited in place; once a member has signed it the
signed version is frozen and a new version is minted. These guard
``WaiversUpdate._maybe_publish_version``.
"""

from sqlalchemy import text

from src.waivers.schema.waivers_schema import (
    WaiverCreateRequest,
    WaiverUpdateData,
    WaiverUpdateRequest,
)
from src.waivers.service.waivers_service import WaiversService


async def _delete_waiver_rows(db_pool, waiver_id) -> None:
    """Remove a waiver + its versions + any signatures (FK-safe order)."""
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


async def test_edit_unsigned_waiver_in_place(db_pool, gym_id):
    """A 0-signature version is edited in place — no version churn."""
    svc = WaiversService(db_pool)
    waiver = await svc.create_waiver(
        WaiverCreateRequest(gym_id=gym_id, name="Liability", body="# v1 body"),
    )
    try:
        v1 = waiver.current_version
        updated = await svc.update_waiver(
            WaiverUpdateRequest(
                waiver_id=waiver.waiver_id,
                gym_id=gym_id,
                data=WaiverUpdateData(body="# v1 body edited"),
            ),
        )
        assert updated.current_version.version_id == v1.version_id
        assert updated.current_version.version_number == v1.version_number
        assert updated.current_version.body == "# v1 body edited"

        versions = await svc.list_versions(waiver.waiver_id, gym_id)
        assert len(versions) == 1  # no new version minted
    finally:
        await _delete_waiver_rows(db_pool, waiver.waiver_id)


async def test_edit_signed_waiver_mints_new_version(db_pool, gym_id, created):
    """Once signed, editing forks a new version; the signed one stays frozen."""
    svc = WaiversService(db_pool)
    member = await created.member(gym_id)
    waiver = await svc.create_waiver(
        WaiverCreateRequest(gym_id=gym_id, name="Signed Waiver", body="# original"),
    )
    try:
        v1 = waiver.current_version
        async with db_pool.session() as session:
            await session.execute(
                text(
                    "INSERT INTO member_waiver_signatures "
                    "(gym_id, member_id, waiver_id, waiver_version_id, "
                    " signer_name, consent_acknowledged, rendered_body, "
                    " content_hash, ip_address, user_agent) "
                    "VALUES (:g, :m, :w, :v, :n, true, :b, :h, "
                    " CAST('0.0.0.0' AS INET), 'test')",
                ),
                {
                    "g": str(gym_id),
                    "m": str(member.member_id),
                    "w": str(waiver.waiver_id),
                    "v": str(v1.version_id),
                    "n": "Test Signer",
                    "b": v1.body,
                    "h": v1.content_hash,
                },
            )
            await session.commit()

        updated = await svc.update_waiver(
            WaiverUpdateRequest(
                waiver_id=waiver.waiver_id,
                gym_id=gym_id,
                data=WaiverUpdateData(body="# revised"),
            ),
        )
        assert updated.current_version.version_id != v1.version_id
        assert updated.current_version.version_number == v1.version_number + 1
        assert updated.current_version.body == "# revised"

        versions = await svc.list_versions(waiver.waiver_id, gym_id)
        assert len(versions) == 2
        v1_after = next(v for v in versions if v.version_id == v1.version_id)
        assert v1_after.body == "# original"  # signed version untouched
        assert v1_after.signature_count == 1
    finally:
        await _delete_waiver_rows(db_pool, waiver.waiver_id)
