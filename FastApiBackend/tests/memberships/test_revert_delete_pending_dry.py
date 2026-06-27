"""Issue #9 regression: the transition revert reuses ``_delete_pending``'s SQL.

Pure unit test (no DB / Stripe / network). ``_revert_db_phase`` must run the
pending-row delete THROUGH ``_delete_pending_in_session`` on the revert's own
shared session (so the delete stays inside the single all-or-nothing revert
txn), instead of re-loading + inlining the delete SQL. And the public
``_delete_pending`` must delegate to the same session-accepting helper.
"""

from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest
from schema.member_membership import StripeSyncStatus

from src.memberships.service.memberships_base import (
    MemberMembershipsBase,
)
from src.memberships.service.memberships_transition_base import (
    MemberMembershipsTransitionBase,
)


def _make_db_pool() -> tuple[MagicMock, MagicMock]:
    """A db_pool whose ``session()`` yields one reusable async session."""
    session = MagicMock()
    session.execute = AsyncMock(return_value=MagicMock())
    session.commit = AsyncMock()
    cm = MagicMock()
    cm.__aenter__ = AsyncMock(return_value=session)
    cm.__aexit__ = AsyncMock(return_value=False)
    db_pool = MagicMock()
    db_pool.session = MagicMock(return_value=cm)
    return db_pool, session


@pytest.mark.asyncio
async def test_revert_calls_delete_pending_in_session_on_shared_session() -> (
    None
):
    db_pool, session = _make_db_pool()
    svc = MemberMembershipsTransitionBase(
        db_pool, MagicMock(), MagicMock(), MagicMock()
    )
    # Successor not yet on Stripe → revert proceeds (no known-residual skip).
    svc._get_sync_status = AsyncMock(return_value=StripeSyncStatus.not_added)
    svc._delete_copied_discounts = AsyncMock()
    svc._delete_pending_in_session = AsyncMock()

    member_id, old_item_id, new_item_id = uuid4(), uuid4(), uuid4()
    await svc._revert_db_phase(member_id, old_item_id, new_item_id)

    # The DRY assertion: the pending delete runs through the shared helper, on
    # the revert's OWN session, exactly once — not a re-loaded inline execute.
    svc._delete_pending_in_session.assert_awaited_once_with(
        session, [new_item_id]
    )
    session.commit.assert_awaited_once()


@pytest.mark.asyncio
async def test_revert_skipped_when_successor_already_applied() -> None:
    """Known-residual guard still holds: no delete once the line landed."""
    db_pool, session = _make_db_pool()
    svc = MemberMembershipsTransitionBase(
        db_pool, MagicMock(), MagicMock(), MagicMock()
    )
    svc._get_sync_status = AsyncMock(return_value=StripeSyncStatus.applied)
    svc._delete_pending_in_session = AsyncMock()

    await svc._revert_db_phase(uuid4(), uuid4(), uuid4())

    svc._delete_pending_in_session.assert_not_awaited()
    session.commit.assert_not_awaited()


@pytest.mark.asyncio
async def test_delete_pending_delegates_to_session_helper() -> None:
    """The public ``_delete_pending`` opens a session, delegates, commits."""
    db_pool, session = _make_db_pool()
    svc = MemberMembershipsBase(db_pool, MagicMock(), MagicMock())
    svc._delete_pending_in_session = AsyncMock()

    item_ids = [uuid4(), uuid4()]
    await svc._delete_pending(item_ids)

    svc._delete_pending_in_session.assert_awaited_once_with(session, item_ids)
    session.commit.assert_awaited_once()


@pytest.mark.asyncio
async def test_delete_pending_empty_is_noop() -> None:
    db_pool, session = _make_db_pool()
    svc = MemberMembershipsBase(db_pool, MagicMock(), MagicMock())
    svc._delete_pending_in_session = AsyncMock()

    await svc._delete_pending([])

    svc._delete_pending_in_session.assert_not_awaited()
    db_pool.session.assert_not_called()
