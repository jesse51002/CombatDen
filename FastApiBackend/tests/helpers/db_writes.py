"""DB-mutating helpers for integration tests.

Keeps write-operation boilerplate out of individual test files when
the same mutation is needed across multiple test modules. All helpers
here are write-only (or read-then-write) — read-only helpers live in
``db_reads.py``.
"""

from __future__ import annotations

from uuid import UUID

from sqlalchemy import text

from src.memberships.service.memberships_linked import MemberMembershipsLinked
from src.shared.database import DirectDatabasePool
from src.shared.paying_member_lock import PayingMemberLock
from src.waivers.service.waivers_service import WaiversService


async def authorize_payer(
    db_pool: DirectDatabasePool,
    member_id: UUID,
    payer_member_id: UUID,
) -> None:
    """Authorize ``payer_member_id`` to pay for ``member_id``.

    Exercises the real sign-gated flow: resolves the gym's payer-auth
    waiver, signs it for the payer via the shared signing service (rendering
    the names in), and inserts the ``member_authorized_payers`` junction row.

    The seeded gym has a payer-auth waiver, so this always succeeds when both
    members belong to it.
    """
    paying_lock = PayingMemberLock(db_pool)
    waivers_svc = WaiversService(db_pool)
    linked = MemberMembershipsLinked(db_pool, paying_lock, waivers_svc)
    payer_auth = await waivers_svc.get_payer_auth_waiver_for_member(member_id)
    operator_id = await _an_employee_id(db_pool, payer_auth.gym_id)
    await linked.link_account(
        member_id,
        payer_member_id,
        waiver_version_id=payer_auth.version_id,
        signer_name="Test Payer",
        consent_acknowledged=True,
        ip_address="0.0.0.0",
        user_agent="test",
        operator_employee_id=operator_id,
    )


async def _an_employee_id(
    db_pool: DirectDatabasePool,
    gym_id: UUID,
) -> UUID:
    """Return any employee_id of a gym (the operator/witness for test signs)."""
    async with db_pool.session() as session:
        result = await session.execute(
            text("SELECT employee_id FROM gym_employees WHERE gym_id = :g LIMIT 1"),
            {"g": str(gym_id)},
        )
        return result.scalar_one()
