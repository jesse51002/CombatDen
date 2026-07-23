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


async def set_points_balance(
    db_pool: DirectDatabasePool,
    member_id: UUID,
    points_balance: int,
) -> None:
    """Force a member's ``points_balance`` to a known value.

    A direct write for test setup only — production never sets the balance
    this way (it goes through redeem / adjust_points), but tests need a
    deterministic starting balance for the redemption edge-case matrix.
    """
    async with db_pool.session() as session:
        await session.execute(
            text(
                "UPDATE members SET points_balance = :balance "
                "WHERE member_id = :id"
            ),
            {"balance": points_balance, "id": str(member_id)},
        )
        await session.commit()


async def set_auth_email_confirmed(
    db_pool: DirectDatabasePool,
    user_id: str,
    *,
    confirmed: bool,
) -> None:
    """Flip a TEST auth user's ``auth.users.email_confirmed_at`` on/off.

    The verified-email identity model rests entirely on that column (every
    identity-resolving query in ``src/shared/auth.py`` requires it to be
    non-NULL), so proving an unverified account is rejected means writing it
    directly — GoTrue exposes no "un-confirm" API. Test setup only: production
    never writes ``auth.users``, and only a user the test itself created (and
    deletes on teardown) may be passed here.
    """
    async with db_pool.session() as session:
        await session.execute(
            text(
                "UPDATE auth.users SET email_confirmed_at = "
                "CASE WHEN :confirmed THEN now() ELSE NULL END "
                "WHERE id = CAST(:id AS UUID)"
            ),
            {"confirmed": confirmed, "id": str(user_id)},
        )
        await session.commit()


async def set_gym_app_links(
    db_pool: DirectDatabasePool,
    gym_id: UUID,
    *,
    app_store_url: str | None,
    play_store_url: str | None,
) -> None:
    """Force a gym's white-label member-app store links to known values.

    A direct write for test setup only: it sets (or, with ``None``, clears
    back to the seed's NULL) the two nullable ``gyms`` columns the public
    ``GET /api/v1/gyms/{gym_id}/app-links`` endpoint resolves. Reversible —
    a test sets them, asserts, then restores NULL in a ``finally`` — so the
    shared seeded gym is left exactly as found.
    """
    async with db_pool.session() as session:
        await session.execute(
            text(
                "UPDATE gyms "
                "SET app_store_url = :app_store_url, "
                "play_store_url = :play_store_url "
                "WHERE gym_id = :gym_id"
            ),
            {
                "app_store_url": app_store_url,
                "play_store_url": play_store_url,
                "gym_id": str(gym_id),
            },
        )
        await session.commit()
