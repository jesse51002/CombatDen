"""C-070 regression — freeze/unfreeze derive the gym server-side.

``verify_gym_employee_for_member`` does not check that a client-supplied
``gym_id`` matches the member, so the freeze path must not trust one. The facade
takes NO ``gym_id`` argument at all: it resolves the gym from the member's OWN
row (immutable ``members.gym_id``) and threads THAT into both payer discovery and
the freeze write. A rowcount guard on the profile write remains as
defense-in-depth.

Pure unit tests (no DB / Stripe / network): the facade is built via ``__new__``
so only the freeze-path collaborators are wired.
"""

from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest

from src.memberships.service.memberships_service import (
    MemberMembershipsService,
)


def _make_lock() -> MagicMock:
    """A paying-member lock whose ``.lock(...)`` is an async context manager."""
    cm = MagicMock()
    cm.__aenter__ = AsyncMock(return_value=None)
    cm.__aexit__ = AsyncMock(return_value=False)
    lock = MagicMock()
    lock.lock = MagicMock(return_value=cm)
    return lock


def _facade(gym_a) -> MemberMembershipsService:
    """A facade with only the freeze-path collaborators wired.

    ``lookup_member_gym_id`` returns ``gym_a`` — the member's real gym.
    """
    facade = MemberMembershipsService.__new__(MemberMembershipsService)
    facade._freeze = MagicMock()
    facade._freeze.lookup_member_gym_id = AsyncMock(return_value=gym_a)
    facade._freeze.freeze = AsyncMock(return_value=None)
    facade._freeze.unfreeze = AsyncMock(return_value=None)
    facade._get_recurring_payers_for_member = AsyncMock(return_value=[uuid4()])
    facade._paying_lock = _make_lock()
    return facade


@pytest.mark.asyncio
async def test_freeze_derives_gym_server_side() -> None:
    member_id = uuid4()
    gym_a = uuid4()  # the member's real gym (looked up server-side)
    facade = _facade(gym_a)

    await facade.freeze(member_id, freeze_months=3, idempotency_key=uuid4())

    facade._freeze.lookup_member_gym_id.assert_awaited_once_with(member_id)
    # Payer discovery + the freeze write are both scoped to the looked-up gym.
    facade._get_recurring_payers_for_member.assert_awaited_once_with(
        member_id, gym_a
    )
    facade._freeze.freeze.assert_awaited_once()
    assert gym_a in facade._freeze.freeze.call_args.args


@pytest.mark.asyncio
async def test_unfreeze_derives_gym_server_side() -> None:
    member_id = uuid4()
    gym_a = uuid4()
    facade = _facade(gym_a)

    await facade.unfreeze(member_id, idempotency_key=uuid4())

    facade._freeze.lookup_member_gym_id.assert_awaited_once_with(member_id)
    facade._get_recurring_payers_for_member.assert_awaited_once_with(
        member_id, gym_a
    )
    facade._freeze.unfreeze.assert_awaited_once()
    assert gym_a in facade._freeze.unfreeze.call_args.args
