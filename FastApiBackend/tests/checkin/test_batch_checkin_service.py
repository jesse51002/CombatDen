"""Unit tests for BatchCheckinService (no DB / no Stripe).

The batch service is driven against a mocked resolver + member gate: the
resolver's ``resolve`` returns a fixed ``ResolvedClass`` and the
gate's ``checkin_member`` is a side-effect that returns a ``CheckinResponse``
(or raises) per member. Covers: the occurrence is resolved exactly once; one
member
raising becomes a ``failed`` item without aborting the rest; an all-failed batch
sets ``all_failed``; duplicate member ids are de-duped; and the
CheckinResponse -> BatchCheckinItemResult status mapping (checked_in /
already_checked_in / skipped).
"""

from datetime import UTC, date, datetime, time
from unittest.mock import AsyncMock, MagicMock
from uuid import UUID, uuid4

from src.checkin.schema.batch_checkin_schema import (
    BatchCheckinItemStatus,
)
from src.checkin.schema.checkin_schema import (
    CheckinResponse,
    CheckinWarning,
    ResolvedClass,
)
from src.checkin.service.batch_checkin_service import BatchCheckinService

_OCCURRENCE_DATE = date(2026, 6, 1)


def _resolved_class() -> ResolvedClass:
    """A resolved occurrence the mocked resolver hands back."""
    return ResolvedClass(
        class_id=uuid4(),
        gym_id=uuid4(),
        occurrence_date=_OCCURRENCE_DATE,
        original_time=time(17, 0),
        occurred_at=datetime(2026, 6, 1, 17, 0, tzinfo=UTC),
        points_worth=50,
        class_name="Evening BJJ",
        max_capacity=None,
        allowed_plan_ids=None,
        instructor_id=None,
        duration_minutes=60,
    )


def _service(resolved_class: ResolvedClass, side_effect) -> tuple[
    BatchCheckinService, MagicMock, MagicMock
]:
    """A batch service over a mocked resolver + member gate.

    The resolver's ``resolve`` returns ``resolved_class``; the gate's
    ``checkin_member`` runs ``side_effect`` (a sync callable returning a
    CheckinResponse or raising), called positionally as
    ``checkin_member(resolved_class, member_id, is_member, ignore_warnings)``.
    """
    resolver = MagicMock()
    resolver.resolve = AsyncMock(return_value=resolved_class)
    member_gate = MagicMock()
    member_gate.checkin_member = AsyncMock(side_effect=side_effect)
    return BatchCheckinService(resolver, member_gate), resolver, member_gate


def _recorded(resolved_class: ResolvedClass, member_id: UUID) -> CheckinResponse:
    """A fresh-record CheckinResponse (log_id set, points awarded)."""
    return CheckinResponse(
        log_id=uuid4(),
        member_id=member_id,
        class_id=resolved_class.class_id,
        already_checked_in=False,
        chosen_plan_id=uuid4(),
        chosen_item_id=uuid4(),
        points_awarded=resolved_class.points_worth,
        skip_reason=None,
        memberships=[],
    )


async def test_one_member_raising_does_not_sink_the_batch() -> None:
    """A member whose check-in raises becomes a ``failed`` item; the other
    members are still processed and the occurrence is resolved once."""
    resolved_class = _resolved_class()
    m1, m2, m3 = uuid4(), uuid4(), uuid4()

    def side_effect(_resolved_class, member_id, _is_member, _ignore):
        if member_id == m2:
            raise RuntimeError("boom")
        return _recorded(resolved_class, member_id)

    service, resolver, member_gate = _service(resolved_class, side_effect)

    response, all_failed = await service.batch_checkin(
        resolved_class.class_id, resolved_class.gym_id, _OCCURRENCE_DATE, [m1, m2, m3], False
    )

    assert all_failed is False
    assert len(response.results) == 3
    by_member = {r.member_id: r for r in response.results}
    assert by_member[m1].status == BatchCheckinItemStatus.checked_in
    assert by_member[m2].status == BatchCheckinItemStatus.failed
    assert by_member[m2].reason == "boom"
    assert by_member[m3].status == BatchCheckinItemStatus.checked_in
    # All three members were attempted despite m2 blowing up.
    assert member_gate.checkin_member.await_count == 3
    # The occurrence is resolved exactly once for the whole batch.
    resolver.resolve.assert_awaited_once()


async def test_all_members_failing_sets_all_failed() -> None:
    """When every member's check-in raises, all_failed is True and every item
    is a ``failed`` carrying the error message."""
    resolved_class = _resolved_class()
    m1, m2 = uuid4(), uuid4()

    def side_effect(_resolved_class, _member_id, _is_member, _ignore):
        raise RuntimeError("db down")

    service, _, _ = _service(resolved_class, side_effect)

    response, all_failed = await service.batch_checkin(
        resolved_class.class_id, resolved_class.gym_id, _OCCURRENCE_DATE, [m1, m2], False
    )

    assert all_failed is True
    assert len(response.results) == 2
    assert all(
        r.status == BatchCheckinItemStatus.failed for r in response.results
    )
    assert all(r.reason == "db down" for r in response.results)


async def test_duplicate_member_ids_are_deduped() -> None:
    """A member listed multiple times yields one result and one check-in."""
    resolved_class = _resolved_class()
    m1 = uuid4()

    def side_effect(_resolved_class, member_id, _is_member, _ignore):
        return _recorded(resolved_class, member_id)

    service, _, member_gate = _service(resolved_class, side_effect)

    response, all_failed = await service.batch_checkin(
        resolved_class.class_id, resolved_class.gym_id, _OCCURRENCE_DATE, [m1, m1, m1], False
    )

    assert all_failed is False
    assert len(response.results) == 1
    assert response.results[0].member_id == m1
    # checkin_member called once despite m1 listed three times.
    assert member_gate.checkin_member.await_count == 1


async def test_status_mapping_covers_recorded_already_and_skipped() -> None:
    """CheckinResponse -> BatchCheckinItemResult: recorded -> checked_in (points
    + ids carried), repeat -> already_checked_in (ids carried, 0 points), no
    log_id -> skipped (reason = skip reason)."""
    resolved_class = _resolved_class()
    recorded_m, already_m, skipped_m = uuid4(), uuid4(), uuid4()

    def already(member_id: UUID) -> CheckinResponse:
        return CheckinResponse(
            log_id=uuid4(),
            member_id=member_id,
            class_id=resolved_class.class_id,
            already_checked_in=True,
            chosen_plan_id=uuid4(),
            chosen_item_id=uuid4(),
            points_awarded=0,
            skip_reason=None,
            memberships=[],
        )

    def skipped(member_id: UUID) -> CheckinResponse:
        return CheckinResponse(
            log_id=None,
            member_id=member_id,
            class_id=resolved_class.class_id,
            already_checked_in=False,
            chosen_plan_id=None,
            chosen_item_id=None,
            points_awarded=0,
            skip_reason=CheckinWarning.no_membership,
            memberships=[],
        )

    def side_effect(_resolved_class, member_id, _is_member, _ignore):
        if member_id == already_m:
            return already(member_id)
        if member_id == skipped_m:
            return skipped(member_id)
        return _recorded(resolved_class, member_id)

    service, _, _ = _service(resolved_class, side_effect)

    response, all_failed = await service.batch_checkin(
        resolved_class.class_id,
        resolved_class.gym_id,
        _OCCURRENCE_DATE,
        [recorded_m, already_m, skipped_m],
        False,
    )

    assert all_failed is False
    by_member = {r.member_id: r for r in response.results}

    checked_in = by_member[recorded_m]
    assert checked_in.status == BatchCheckinItemStatus.checked_in
    assert checked_in.points_awarded == resolved_class.points_worth
    assert checked_in.log_id is not None
    assert checked_in.chosen_plan_id is not None
    assert checked_in.reason is None

    repeat = by_member[already_m]
    assert repeat.status == BatchCheckinItemStatus.already_checked_in
    assert repeat.points_awarded == 0
    assert repeat.log_id is not None
    assert repeat.reason is None

    skip = by_member[skipped_m]
    assert skip.status == BatchCheckinItemStatus.skipped
    assert skip.reason == "no_membership"
    assert skip.log_id is None
    assert skip.points_awarded == 0


async def test_warnings_propagate_to_batch_item() -> None:
    """A staff (warned) check-in carries its warnings onto the batch item."""
    resolved_class = _resolved_class()
    member = uuid4()

    def warned(_resolved_class, member_id, _is_member, _ignore):
        # An OVERRIDDEN staff check-in: recorded (log_id set) with warnings.
        return CheckinResponse(
            log_id=uuid4(),
            member_id=member_id,
            class_id=resolved_class.class_id,
            already_checked_in=False,
            chosen_plan_id=None,
            chosen_item_id=None,
            points_awarded=resolved_class.points_worth,
            skip_reason=None,
            warnings=[CheckinWarning.no_membership],
            memberships=[],
        )

    service, _, _ = _service(resolved_class, warned)

    response, all_failed = await service.batch_checkin(
        resolved_class.class_id, resolved_class.gym_id, _OCCURRENCE_DATE, [member], False
    )

    assert all_failed is False
    item = response.results[0]
    assert item.status == BatchCheckinItemStatus.checked_in
    assert item.warnings == [CheckinWarning.no_membership]


async def test_needs_confirmation_maps_to_needs_confirmation() -> None:
    """A staff check-in held for confirmation (requires_confirmation, not
    recorded) -> a needs_confirmation item carrying the warnings + primary
    reason, nothing written."""
    resolved_class = _resolved_class()
    member = uuid4()

    def needs_confirm(_resolved_class, member_id, _is_member, _ignore):
        return CheckinResponse(
            log_id=None,
            member_id=member_id,
            class_id=resolved_class.class_id,
            already_checked_in=False,
            chosen_plan_id=None,
            chosen_item_id=None,
            points_awarded=0,
            skip_reason=None,
            warnings=[CheckinWarning.no_membership],
            requires_confirmation=True,
            memberships=[],
        )

    service, _, _ = _service(resolved_class, needs_confirm)

    response, all_failed = await service.batch_checkin(
        resolved_class.class_id, resolved_class.gym_id, _OCCURRENCE_DATE, [member], False
    )

    assert all_failed is False
    item = response.results[0]
    assert item.status == BatchCheckinItemStatus.needs_confirmation
    assert item.reason == "no_membership"
    assert item.warnings == [CheckinWarning.no_membership]
    assert item.log_id is None
    assert item.points_awarded == 0
