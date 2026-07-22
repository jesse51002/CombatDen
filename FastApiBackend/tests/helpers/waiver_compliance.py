"""Waiver-gate test setup: make a member signed-up-to-date, then undo it.

The check-in gate is a LEGAL gate: a member whose current memberships' plans
attach a waiver they have not signed (at or above that waiver's re-sign FLOOR)
is warned — a staff check-in comes back ``requires_confirmation`` and records
NOTHING (see ``src/checkin/sql/checkin_unsigned_waivers.sql``). The seed
deliberately leaves every existing member UNSIGNED so the CRM demo shows the
gate + the wizard sign step, so any suite that wants a member to actually
check in must establish waiver compliance itself rather than hope the seed
picked a signed member.

``WaiverCompliance`` does exactly that, through the real API:

* ``GET /api/v1/waivers/signatures/by-member/{member_id}`` is the API mirror of
  the check-in gate's required-set query (same required + floor semantics), so
  the rows it flags ``required and not meets_floor`` are precisely what the
  gate would warn about.
* ``POST /api/v1/waivers/{waiver_id}/signatures`` is the ONE signing path — it
  version-locks, renders the ``{{placeholder}}`` body, and freezes the
  ``rendered_body`` + ``content_hash`` and the legal-evidence columns. A raw
  INSERT would bypass all of that, so it is never used here.

``member_waiver_signatures`` is append-only for ``authenticated`` (UPDATE and
DELETE are revoked), but tests connect as ``postgres``, so teardown deletes the
rows it created — BY ``signature_id``, never by member: a seeded member may
already hold payer-auth signatures that are not ours to touch.
"""

from __future__ import annotations

import asyncio
from typing import Any

import httpx
from sqlalchemy import bindparam, text

from src.shared.database import DirectDatabasePool

# The typed name + capture stamped on every signature this helper creates.
_SIGNER_NAME = "Integration Test Signer"


def _run_async(coro: Any) -> Any:
    """Run a coroutine on a fresh loop (pytest-asyncio owns the main loop)."""
    loop = asyncio.new_event_loop()
    try:
        return loop.run_until_complete(coro)
    finally:
        loop.close()


async def _delete_signatures(signature_ids: list[str]) -> None:
    """Delete exactly the signature rows this helper created."""
    pool = DirectDatabasePool()
    try:
        stmt = text(
            "DELETE FROM member_waiver_signatures "
            "WHERE signature_id IN :signature_ids"
        ).bindparams(bindparam("signature_ids", expanding=True))
        async with pool.session() as session:
            await session.execute(stmt, {"signature_ids": signature_ids})
            await session.commit()
    finally:
        await pool.engine.dispose()


class WaiverCompliance:
    """Signs whatever the check-in gate would warn about, and cleans up after.

    Usage (session-scoped fixture):

        compliance = WaiverCompliance(api, GYM_ID)
        compliance.ensure_signed(member_id)
        yield ...
        compliance.cleanup()
    """

    def __init__(self, api: httpx.Client, gym_id: str) -> None:
        self._api = api
        self._gym_id = gym_id
        self._created: list[str] = []

    def ensure_signed(self, member_id: str) -> None:
        """Sign every waiver ``member_id`` still owes for the check-in gate.

        A member with no current membership requires nothing, so this is a
        no-op for them (matching the gate, whose required set comes from the
        member's active/frozen memberships' plans).
        """
        resp = self._api.get(
            f"/api/v1/waivers/signatures/by-member/{member_id}",
            params={"gym_id": self._gym_id},
        )
        assert resp.status_code == 200, resp.text
        for row in resp.json():
            if row["is_deleted"] or not row["required"] or row["meets_floor"]:
                continue
            version_id = row["current_version_id"]
            assert version_id is not None, (
                f"Waiver {row['waiver_id']} is required but has no current "
                "version to sign"
            )
            signed = self._api.post(
                f"/api/v1/waivers/{row['waiver_id']}/signatures",
                json={
                    "gym_id": self._gym_id,
                    "member_id": member_id,
                    "waiver_version_id": version_id,
                    "signer_name": _SIGNER_NAME,
                    "consent_acknowledged": True,
                },
            )
            assert signed.status_code == 201, signed.text
            self._created.append(signed.json()["signature_id"])

    def cleanup(self) -> None:
        """Delete every signature this helper created (seed rows untouched)."""
        if not self._created:
            return
        signature_ids = list(self._created)
        self._created.clear()
        _run_async(_delete_signatures(signature_ids))
