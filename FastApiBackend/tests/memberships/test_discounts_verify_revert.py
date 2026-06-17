"""Unit tests: add/remove discounts revert their DB change on a failed sync.

Piece 2 wires ``add_discounts`` / ``remove_discounts`` through ``sync_or_revert``
so a sync that fails (or, for an add, doesn't confirm the writeback) undoes the DB
change instead of leaving it stranded — matching the cancel / update_price callers
and the sync-guide caller contract.

Pure unit tests: the service is built with mocked deps and its DB-touching helpers
are stubbed, so no DB / Stripe is touched. The real ``sync_or_revert`` runs (that
is the wiring under test).
"""

from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

import pytest
from schema.membership_plan import PlanType

import src.shared.db_schema_path  # noqa: F401
from src.memberships.service.memberships_discounts import (
    MemberMembershipsDiscounts,
)
from src.shared.db_first_helpers import SyncNotConfirmedError


def _membership_row() -> dict:
    """A membership row that passes _validate_apply (recurring + on Stripe)."""
    return {
        "gym_id": uuid4(),
        "paid_by_member_id": uuid4(),
        "timezone": "America/Chicago",
        "cancel_date": None,
        "end_date": None,
        "plan_type": PlanType.recurring,
        "stripe_item_id": "si_x",
    }


def _service() -> MemberMembershipsDiscounts:
    """Service with mocked deps + a stubbed membership read."""
    svc = MemberMembershipsDiscounts(
        db_pool=MagicMock(),
        payment_sync_service=AsyncMock(),
        gym_stripe_service=MagicMock(),
    )
    svc._get_membership = AsyncMock(return_value=_membership_row())
    return svc


async def test_add_reverts_inserts_when_sync_raises() -> None:
    """A sync exception on add deletes exactly the inserted rows + propagates."""
    svc = _service()
    item_id, member_id = uuid4(), uuid4()
    inserted = [uuid4(), uuid4()]
    svc.add_applied_discounts = AsyncMock(return_value=inserted)
    svc.delete_applied_discounts = AsyncMock()
    svc._payment_sync.update_payments_recurring = AsyncMock(
        side_effect=RuntimeError("boom"),
    )

    with pytest.raises(RuntimeError):
        await svc.add_discounts(
            item_id, member_id, [uuid4()], idempotency_key=uuid4(),
        )

    svc.delete_applied_discounts.assert_awaited_once_with(member_id, inserted)


async def test_add_reverts_inserts_when_sync_unconfirmed() -> None:
    """An unconfirmed writeback on add reverts + raises SyncNotConfirmedError."""
    svc = _service()
    item_id, member_id = uuid4(), uuid4()
    inserted = [uuid4()]
    svc.add_applied_discounts = AsyncMock(return_value=inserted)
    svc.delete_applied_discounts = AsyncMock()
    svc._payment_sync.update_payments_recurring = AsyncMock()  # succeeds
    svc._applied_discounts_confirmed = AsyncMock(return_value=False)

    with pytest.raises(SyncNotConfirmedError):
        await svc.add_discounts(
            item_id, member_id, [uuid4()], idempotency_key=uuid4(),
        )

    svc.delete_applied_discounts.assert_awaited_once_with(member_id, inserted)


async def test_add_keeps_inserts_when_sync_confirms() -> None:
    """A confirmed add does not revert."""
    svc = _service()
    item_id, member_id = uuid4(), uuid4()
    svc.add_applied_discounts = AsyncMock(return_value=[uuid4()])
    svc.delete_applied_discounts = AsyncMock()
    svc._payment_sync.update_payments_recurring = AsyncMock()
    svc._applied_discounts_confirmed = AsyncMock(return_value=True)

    await svc.add_discounts(
        item_id, member_id, [uuid4()], idempotency_key=uuid4(),
    )

    svc.delete_applied_discounts.assert_not_awaited()


async def test_remove_restores_rows_when_sync_raises() -> None:
    """A sync exception on remove re-inserts the snapshot + propagates."""
    svc = _service()
    item_id, member_id = uuid4(), uuid4()
    applied_ids = [uuid4()]
    snapshot = [
        {
            "item_id": uuid4(),
            "member_id": member_id,
            "gym_id": uuid4(),
            "value_id": uuid4(),
            "end_date": None,
            "stripe_sync_status": "applied",
        }
    ]
    svc._read_applied_discounts_by_ids = AsyncMock(return_value=snapshot)
    svc.delete_applied_discounts = AsyncMock()
    svc._restore_applied_discounts = AsyncMock()
    svc._payment_sync.update_payments_recurring = AsyncMock(
        side_effect=RuntimeError("boom"),
    )

    with pytest.raises(RuntimeError):
        await svc.remove_discounts(
            item_id, member_id, applied_ids, idempotency_key=uuid4(),
        )

    svc.delete_applied_discounts.assert_awaited_once_with(member_id, applied_ids)
    svc._restore_applied_discounts.assert_awaited_once_with(snapshot)


async def test_remove_does_not_restore_when_sync_succeeds() -> None:
    """A successful remove never re-inserts the removed rows."""
    svc = _service()
    item_id, member_id = uuid4(), uuid4()
    applied_ids = [uuid4()]
    svc._read_applied_discounts_by_ids = AsyncMock(return_value=[])
    svc.delete_applied_discounts = AsyncMock()
    svc._restore_applied_discounts = AsyncMock()
    svc._payment_sync.update_payments_recurring = AsyncMock()  # succeeds

    await svc.remove_discounts(
        item_id, member_id, applied_ids, idempotency_key=uuid4(),
    )

    svc._restore_applied_discounts.assert_not_awaited()
