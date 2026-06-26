"""Regression tests for Group G3 billing fixes.

Pure unit tests (no DB / Stripe / network):

* **C-079** — the staff-managed billing writes (start, freeze, unfreeze,
  mark-paid-cash, charge-card, refund) must gate on
  ``verify_gym_employee_for_member`` (staff only), NOT
  ``verify_can_view_member`` (which lets the member themselves through).
* **C-070** — the freeze / unfreeze profile write must fail loudly when the
  client-supplied ``gym_id`` does not match the member's row (rowcount != 1),
  instead of silently updating 0 rows and reporting success.
* **C-075** — a busy payer lock (``LockBusyError``) maps to HTTP 409, the
  documented contract, not an unhandled 500.
"""

from datetime import date
from unittest.mock import AsyncMock, MagicMock

import pytest

from src.main import _handle_lock_busy_error
from src.memberships.memberships_router import (
    charge_member_card,
    freeze_membership,
    mark_membership_paid_cash,
    refund_charge,
    start_membership,
    unfreeze_membership,
)
from src.memberships.service.memberships_freeze import (
    MemberMembershipsFreeze,
)
from src.shared.paying_member_lock import LockBusyError


def _make_auth() -> MagicMock:
    """An auth double recording which member guard a handler invokes."""
    auth = MagicMock()
    auth.get_current_user = MagicMock(return_value={})
    auth.verify_gym_employee_for_member = AsyncMock(return_value=None)
    auth.verify_can_view_member = AsyncMock(return_value=None)
    return auth


def _make_session(rowcount: int) -> tuple[MagicMock, MagicMock, AsyncMock]:
    """A fake db_pool whose session yields a result with ``rowcount``."""
    session = MagicMock()
    session.execute = AsyncMock(return_value=MagicMock(rowcount=rowcount))
    session.commit = AsyncMock()
    cm = MagicMock()
    cm.__aenter__ = AsyncMock(return_value=session)
    cm.__aexit__ = AsyncMock(return_value=False)
    db_pool = MagicMock()
    db_pool.session = MagicMock(return_value=cm)
    return db_pool, session, session.commit


# ── C-079: staff-only guard on the billing writes ──────────────────


@pytest.mark.asyncio
async def test_freeze_uses_staff_only_guard() -> None:
    auth = _make_auth()
    service = MagicMock()
    service.freeze = AsyncMock(return_value=None)

    await freeze_membership(
        request=MagicMock(),
        credentials=MagicMock(),
        auth=auth,
        memberships_service=service,
    )

    auth.verify_gym_employee_for_member.assert_awaited_once()
    auth.verify_can_view_member.assert_not_awaited()


@pytest.mark.asyncio
async def test_unfreeze_uses_staff_only_guard() -> None:
    auth = _make_auth()
    service = MagicMock()
    service.unfreeze = AsyncMock(return_value=None)

    await unfreeze_membership(
        request=MagicMock(),
        credentials=MagicMock(),
        auth=auth,
        memberships_service=service,
    )

    auth.verify_gym_employee_for_member.assert_awaited_once()
    auth.verify_can_view_member.assert_not_awaited()


@pytest.mark.asyncio
async def test_mark_paid_cash_uses_staff_only_guard() -> None:
    auth = _make_auth()
    service = MagicMock()
    service.mark_paid_cash = AsyncMock(return_value=None)
    tasks_service = MagicMock()
    tasks_service.assert_memberships_not_in_task = AsyncMock(return_value=None)

    await mark_membership_paid_cash(
        request=MagicMock(),
        credentials=MagicMock(),
        auth=auth,
        memberships_service=service,
        tasks_service=tasks_service,
    )

    auth.verify_gym_employee_for_member.assert_awaited_once()
    auth.verify_can_view_member.assert_not_awaited()


@pytest.mark.asyncio
async def test_charge_card_uses_staff_only_guard() -> None:
    auth = _make_auth()
    service = MagicMock()
    service.charge_card = AsyncMock(return_value=None)

    await charge_member_card(
        request=MagicMock(),
        credentials=MagicMock(),
        auth=auth,
        memberships_service=service,
    )

    auth.verify_gym_employee_for_member.assert_awaited_once()
    auth.verify_can_view_member.assert_not_awaited()


@pytest.mark.asyncio
async def test_refund_uses_staff_only_guard() -> None:
    auth = _make_auth()
    refund_service = MagicMock()
    refund_service.refund_charge = AsyncMock(return_value=MagicMock())

    await refund_charge(
        request=MagicMock(),
        credentials=MagicMock(),
        auth=auth,
        refund_service=refund_service,
    )

    auth.verify_gym_employee_for_member.assert_awaited_once()
    auth.verify_can_view_member.assert_not_awaited()


@pytest.mark.asyncio
async def test_start_uses_staff_only_guard() -> None:
    auth = _make_auth()
    service = MagicMock()
    service.start = AsyncMock(return_value=MagicMock())
    request = MagicMock()
    request.memberships = [MagicMock(member_id="m1")]

    await start_membership(
        request=request,
        response=MagicMock(),
        credentials=MagicMock(),
        auth=auth,
        memberships_service=service,
    )

    auth.verify_gym_employee_for_member.assert_awaited()
    auth.verify_can_view_member.assert_not_awaited()


# ── C-070: gym_id mismatch must fail loudly (rowcount guard) ────────


@pytest.mark.asyncio
async def test_freeze_profile_raises_on_gym_mismatch() -> None:
    db_pool, _session, commit = _make_session(rowcount=0)
    svc = MemberMembershipsFreeze(db_pool, MagicMock(), MagicMock())

    with pytest.raises(ValueError, match="not found"):
        await svc._crm_freeze_profile(
            MagicMock(), MagicMock(), date.today(), date.today()
        )
    commit.assert_not_awaited()


@pytest.mark.asyncio
async def test_freeze_profile_commits_on_match() -> None:
    db_pool, _session, commit = _make_session(rowcount=1)
    svc = MemberMembershipsFreeze(db_pool, MagicMock(), MagicMock())

    await svc._crm_freeze_profile(
        MagicMock(), MagicMock(), date.today(), date.today()
    )
    commit.assert_awaited_once()


@pytest.mark.asyncio
async def test_unfreeze_profile_raises_on_gym_mismatch() -> None:
    db_pool, _session, commit = _make_session(rowcount=0)
    svc = MemberMembershipsFreeze(db_pool, MagicMock(), MagicMock())

    with pytest.raises(ValueError, match="not found"):
        await svc._crm_unfreeze_profile(MagicMock(), MagicMock())
    commit.assert_not_awaited()


# ── C-075: LockBusyError -> 409 ────────────────────────────────────


@pytest.mark.asyncio
async def test_lock_busy_error_maps_to_409() -> None:
    response = await _handle_lock_busy_error(
        MagicMock(), LockBusyError("payer:abc")
    )
    assert response.status_code == 409
