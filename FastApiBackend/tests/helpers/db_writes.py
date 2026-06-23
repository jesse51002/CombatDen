"""DB-mutating helpers for integration tests.

Keeps write-operation boilerplate out of individual test files when
the same mutation is needed across multiple test modules. All helpers
here are write-only (or read-then-write) — read-only helpers live in
``db_reads.py``.
"""

from __future__ import annotations

from uuid import UUID

from src.memberships.service.memberships_linked import MemberMembershipsLinked
from src.shared.database import DirectDatabasePool
from src.shared.paying_member_lock import PayingMemberLock
from src.waivers.service.waivers.waivers_service import WaiversService


async def authorize_payer(
    db_pool: DirectDatabasePool,
    member_id: UUID,
    payer_member_id: UUID,
) -> None:
    """Authorize ``payer_member_id`` to pay for ``member_id``.

    Exercises the real sign-gated flow: resolves the gym's default
    authorized-payer waiver, records a signature for the payer, and
    inserts the ``member_authorized_payers`` junction row — all in one
    transaction.

    The seeded gym has a default waiver, so this always succeeds when
    both members belong to it.
    """
    paying_lock = PayingMemberLock(db_pool)
    waivers_svc = WaiversService(db_pool)
    linked = MemberMembershipsLinked(db_pool, paying_lock, waivers_svc)
    await linked.link_account(
        member_id,
        payer_member_id,
        signer_name="Test Payer",
        consent_acknowledged=True,
    )
