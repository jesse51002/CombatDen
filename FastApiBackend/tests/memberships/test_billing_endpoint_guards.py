"""Regression tests for Group G3 billing fixes.

Pure unit tests (no DB / Stripe / network):

* **C-079** — the staff-managed billing writes (start, cancel, reprice,
  upgrade, add/remove-discounts, freeze, unfreeze, mark-paid-cash,
  retry-card, charge-card, refund) must gate on ``verify_gym_employee_for_member``
  AT THE ``STAFF`` ROLE SET (owner/admin/front_desk) — the money ops are
  front-desk work. Each test pins the awaited ``staff_roles`` kwarg so a
  regression that widened a money op to ``ALL_EMPLOYEES`` (trainer) or
  narrowed it to ``OWNER_ADMIN`` fails loudly instead of passing silently.
* **C-070** — the freeze / unfreeze profile write must fail loudly when the
  client-supplied ``gym_id`` does not match the member's row (rowcount != 1),
  instead of silently updating 0 rows and reporting success.
* **C-075** — a busy payer lock (``LockBusyError``) maps to HTTP 409, the
  documented contract, not an unhandled 500. Two halves, and the second is the
  one that actually bites: the global handler must map the type (it always
  did), **and** every router handler that TAKES the lock must let the error out
  instead of swallowing it in its own ``except Exception`` → 500. The lock is
  acquired INSIDE each handler's ``try``, and ``LockBusyError`` subclasses
  ``Exception`` directly, so without a typed re-raise arm the global handler can
  never fire. ``test_lock_busy_error_propagates_out_of_locking_handler``
  parametrizes that over every locking handler in the router.
"""

import inspect
from datetime import date
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest
from fastapi import Response

from src.main import _handle_lock_busy_error
from src.memberships.memberships_router import (
    add_membership_discounts,
    cancel_membership,
    charge_member_card,
    freeze_membership,
    mark_membership_paid_cash,
    preview_cancel_membership,
    preview_start_membership,
    preview_upgrade_membership,
    refund_charge,
    remove_membership_discounts,
    retry_membership_card,
    start_membership,
    unfreeze_membership,
    update_membership_price,
    upgrade_membership,
)
from src.memberships.memberships_schema import (
    MemberMembershipsRetryCardRequest,
)
from src.memberships.service.memberships_freeze import (
    MemberMembershipsFreeze,
)
from src.shared.auth import STAFF
from src.shared.paying_member_lock import LockBusyError


def _make_auth() -> MagicMock:
    """An auth double recording that a handler invokes the staff guard."""
    auth = MagicMock()
    auth.get_current_user = MagicMock(return_value={})
    auth.verify_gym_employee_for_member = AsyncMock(return_value=None)
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


def _assert_guarded_at_staff(auth: MagicMock) -> None:
    """The handler awaited ``verify_gym_employee_for_member`` at the ``STAFF``
    role set — the exact set matters, not just that the gate was called."""
    assert auth.verify_gym_employee_for_member.await_args.kwargs[
        "staff_roles"
    ] is STAFF


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
    _assert_guarded_at_staff(auth)


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
    _assert_guarded_at_staff(auth)


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
    _assert_guarded_at_staff(auth)


@pytest.mark.asyncio
async def test_retry_card_uses_staff_only_guard() -> None:
    auth = _make_auth()
    service = MagicMock()
    service.retry_card = AsyncMock(return_value=None)
    tasks_service = MagicMock()
    tasks_service.assert_memberships_not_in_task = AsyncMock(return_value=None)

    # A real body: the handler now returns a typed outcome echoing these ids.
    await retry_membership_card(
        request=MemberMembershipsRetryCardRequest(
            item_id=uuid4(),
            member_id=uuid4(),
            idempotency_key=uuid4(),
        ),
        response=Response(),
        credentials=MagicMock(),
        auth=auth,
        memberships_service=service,
        tasks_service=tasks_service,
    )

    auth.verify_gym_employee_for_member.assert_awaited_once()
    _assert_guarded_at_staff(auth)


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
    _assert_guarded_at_staff(auth)


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
    _assert_guarded_at_staff(auth)


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
    _assert_guarded_at_staff(auth)


@pytest.mark.asyncio
async def test_preview_start_uses_staff_only_guard() -> None:
    auth = _make_auth()
    service = MagicMock()
    service.preview_start = AsyncMock(return_value=MagicMock())
    request = MagicMock()
    request.memberships = [MagicMock(member_id="m1")]

    await preview_start_membership(
        request=request,
        credentials=MagicMock(),
        auth=auth,
        memberships_service=service,
    )

    auth.verify_gym_employee_for_member.assert_awaited()
    _assert_guarded_at_staff(auth)


@pytest.mark.asyncio
async def test_cancel_uses_staff_only_guard() -> None:
    auth = _make_auth()
    service = MagicMock()
    service.cancel_many = AsyncMock(return_value={})
    tasks_service = MagicMock()
    tasks_service.assert_memberships_not_in_task = AsyncMock(return_value=None)

    await cancel_membership(
        request=MagicMock(),
        credentials=MagicMock(),
        auth=auth,
        memberships_service=service,
        tasks_service=tasks_service,
    )

    auth.verify_gym_employee_for_member.assert_awaited_once()
    _assert_guarded_at_staff(auth)


@pytest.mark.asyncio
async def test_add_discounts_uses_staff_only_guard() -> None:
    """A member must not be able to grant themselves a discount."""
    auth = _make_auth()
    service = MagicMock()
    service.add_discounts = AsyncMock(return_value=None)
    tasks_service = MagicMock()
    tasks_service.assert_memberships_not_in_task = AsyncMock(return_value=None)

    await add_membership_discounts(
        request=MagicMock(),
        credentials=MagicMock(),
        auth=auth,
        memberships_service=service,
        tasks_service=tasks_service,
    )

    auth.verify_gym_employee_for_member.assert_awaited_once()
    _assert_guarded_at_staff(auth)


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


# Every membership handler whose service takes ``PayingMemberLock``, paired with
# the facade method that takes it. The three that are absent are absent on
# purpose: ``cancel_one_time_membership`` is delegated bare (a pure DB date
# write), ``batch_reprice_plan`` only creates a task (the lock is taken in the
# background executor, outside the request), and ``refund_charge`` serializes on
# a FOR UPDATE row lock, not the payer lock.
_LOCKING_HANDLERS = [
    (cancel_membership, "cancel_many"),
    (freeze_membership, "freeze"),
    (unfreeze_membership, "unfreeze"),
    (start_membership, "start"),
    (update_membership_price, "update_price"),
    (upgrade_membership, "upgrade"),
    (preview_upgrade_membership, "upgrade_preview"),
    (preview_start_membership, "preview_start"),
    (preview_cancel_membership, "preview_cancel_many"),
    (add_membership_discounts, "add_discounts"),
    (remove_membership_discounts, "remove_discounts"),
    (mark_membership_paid_cash, "mark_paid_cash"),
    (retry_membership_card, "retry_card"),
    (charge_member_card, "charge_card"),
]


def _handler_kwargs(handler, service: MagicMock) -> dict:
    """Build the doubles each handler's signature actually asks for."""
    request = MagicMock()
    # start / preview-start iterate the item list to run the per-member guard.
    request.memberships = [MagicMock(member_id=uuid4())]

    tasks_service = MagicMock()
    tasks_service.assert_memberships_not_in_task = AsyncMock(return_value=None)

    available = {
        "request": request,
        "response": Response(),
        "credentials": MagicMock(),
        "auth": _make_auth(),
        "memberships_service": service,
        "tasks_service": tasks_service,
    }
    params = inspect.signature(handler).parameters
    return {k: v for k, v in available.items() if k in params}


@pytest.mark.parametrize(
    ("handler", "method"),
    _LOCKING_HANDLERS,
    ids=[handler.__name__ for handler, _ in _LOCKING_HANDLERS],
)
@pytest.mark.asyncio
async def test_lock_busy_error_propagates_out_of_locking_handler(
    handler,
    method: str,
) -> None:
    """A busy payer must ESCAPE the handler so the global 409 handler sees it.

    The lock is acquired inside the handler's ``try`` and ``LockBusyError``
    subclasses ``Exception``, so the generic ``except Exception`` → 500 arm
    would swallow it and the front desk would get an opaque server error for a
    perfectly retryable conflict (e.g. clicking Retry Card while a bulk reprice
    holds the payer). The fix is a typed arm that re-raises; this test is what
    proves it, since a swallowed error shows up as an ``HTTPException(500)``
    instead of the ``LockBusyError`` asserted here.
    """
    service = MagicMock()
    setattr(
        service,
        method,
        AsyncMock(side_effect=LockBusyError("payer:abc")),
    )

    with pytest.raises(LockBusyError):
        await handler(**_handler_kwargs(handler, service))


@pytest.mark.asyncio
async def test_propagated_lock_busy_error_becomes_a_409_body() -> None:
    """End-to-end of the two halves: what escapes a handler is what the global
    handler formats — a 409 with a plain-string ``detail``, never a 500."""
    service = MagicMock()
    service.retry_card = AsyncMock(side_effect=LockBusyError("payer:abc"))

    with pytest.raises(LockBusyError) as caught:
        await retry_membership_card(
            **_handler_kwargs(retry_membership_card, service)
        )

    response = await _handle_lock_busy_error(MagicMock(), caught.value)
    assert response.status_code == 409
    assert b"payer:abc" in response.body
