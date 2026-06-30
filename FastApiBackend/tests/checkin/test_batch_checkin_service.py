"""Unit tests for BatchCheckinService (no DB / no Stripe).

The batch service is driven against a mocked ``CheckinService``:
``resolve_occurrence`` returns a fixed ``OccurrenceContext`` and
``checkin_member`` is a side-effect that returns a ``CheckinResponse`` (or
raises) per member. Covers: the occurrence is resolved exactly once; one member
raising becomes a ``failed`` item without aborting the rest; an all-failed batch
sets ``all_failed``; duplicate member ids are de-duped; and the
CheckinResponse -> BatchCheckinItemResult status mapping (checked_in /
already_checked_in / skipped).
"""

from datetime import UTC, date, datetime
from unittest.mock import AsyncMock, MagicMock
from uuid import UUID, uuid4

from src.checkin.schema.batch_checkin_schema import (
    BatchCheckinItemStatus,
)
from src.checkin.schema.checkin_schema import (
    CheckinResponse,
    CheckinWarning,
    OccurrenceContext,
)
from src.checkin.service.batch_checkin_service import BatchCheckinService

_OCCURRENCE_DATE = date(2026, 6, 1)


def _ctx() -> OccurrenceContext:
    """A resolved occurrence the mocked checkin_service hands back."""
    return OccurrenceContext(
        class_history_id=uuid4(),
        class_id=uuid4(),
        gym_id=uuid4(),
        occurred_at=datetime(2026, 6, 1, 17, 0, tzinfo=UTC),
        points_worth=50,
        class_name="Evening BJJ",
        max_capacity=None,
        allowed_plan_ids=None,
        instructor_id=None,
        duration_minutes=60,
    )


def _service(ctx: OccurrenceContext, side_effect) -> tuple[
    BatchCheckinService, MagicMock
]:
    """A batch service over a mocked CheckinService.

    ``resolve_occurrence`` returns ``ctx``; ``checkin_member`` runs
    ``side_effect`` (a sync callable returning a CheckinResponse or raising).
    """
    checkin_service = MagicMock()
    checkin_service.resolve_occurrence = AsyncMock(return_value=ctx)
    checkin_service.checkin_member = AsyncMock(side_effect=side_effect)
    return BatchCheckinService(checkin_service), checkin_service


def _recorded(ctx: OccurrenceContext, member_id: UUID) -> CheckinResponse:
    """A fresh-record CheckinResponse (log_id set, points awarded)."""
    return CheckinResponse(
        log_id=uuid4(),
        member_id=member_id,
        class_history_id=ctx.class_history_id,
        class_id=ctx.class_id,
        already_checked_in=False,
        chosen_plan_id=uuid4(),
        chosen_item_id=uuid4(),
        points_awarded=ctx.points_worth,
        skip_reason=None,
        memberships=[],
    )


async def test_one_member_raising_does_not_sink_the_batch() -> None:
    """A member whose check-in raises becomes a ``failed`` item; the other
    members are still processed and the occurrence is resolved once."""
    ctx = _ctx()
    m1, m2, m3 = uuid4(), uuid4(), uuid4()

    def side_effect(_ctx, member_id, _allow):
        if member_id == m2:
            raise RuntimeError("boom")
        return _recorded(ctx, member_id)

    service, checkin_service = _service(ctx, side_effect)

    response, all_failed = await service.batch_checkin(
        ctx.class_id, ctx.gym_id, _OCCURRENCE_DATE, [m1, m2, m3], False
    )

    assert all_failed is False
    assert response.class_history_id == ctx.class_history_id
    assert len(response.results) == 3
    by_member = {r.member_id: r for r in response.results}
    assert by_member[m1].status == BatchCheckinItemStatus.checked_in
    assert by_member[m2].status == BatchCheckinItemStatus.failed
    assert by_member[m2].reason == "boom"
    assert by_member[m3].status == BatchCheckinItemStatus.checked_in
    # All three members were attempted despite m2 blowing up.
    assert checkin_service.checkin_member.await_count == 3
    # The occurrence is materialized exactly once for the whole batch.
    checkin_service.resolve_occurrence.assert_awaited_once()


async def test_all_members_failing_sets_all_failed() -> None:
    """When every member's check-in raises, all_failed is True and every item
    is a ``failed`` carrying the error message."""
    ctx = _ctx()
    m1, m2 = uuid4(), uuid4()

    def side_effect(_ctx, _member_id, _allow):
        raise RuntimeError("db down")

    service, _ = _service(ctx, side_effect)

    response, all_failed = await service.batch_checkin(
        ctx.class_id, ctx.gym_id, _OCCURRENCE_DATE, [m1, m2], False
    )

    assert all_failed is True
    assert len(response.results) == 2
    assert all(
        r.status == BatchCheckinItemStatus.failed for r in response.results
    )
    assert all(r.reason == "db down" for r in response.results)


async def test_duplicate_member_ids_are_deduped() -> None:
    """A member listed multiple times yields one result and one check-in."""
    ctx = _ctx()
    m1 = uuid4()

    def side_effect(_ctx, member_id, _allow):
        return _recorded(ctx, member_id)

    service, checkin_service = _service(ctx, side_effect)

    response, all_failed = await service.batch_checkin(
        ctx.class_id, ctx.gym_id, _OCCURRENCE_DATE, [m1, m1, m1], False
    )

    assert all_failed is False
    assert len(response.results) == 1
    assert response.results[0].member_id == m1
    # checkin_member called once despite m1 listed three times.
    assert checkin_service.checkin_member.await_count == 1


async def test_status_mapping_covers_recorded_already_and_skipped() -> None:
    """CheckinResponse -> BatchCheckinItemResult: recorded -> checked_in (points
    + ids carried), repeat -> already_checked_in (ids carried, 0 points), no
    log_id -> skipped (reason = skip reason)."""
    ctx = _ctx()
    recorded_m, already_m, skipped_m = uuid4(), uuid4(), uuid4()

    def already(member_id: UUID) -> CheckinResponse:
        return CheckinResponse(
            log_id=uuid4(),
            member_id=member_id,
            class_history_id=ctx.class_history_id,
            class_id=ctx.class_id,
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
            class_history_id=ctx.class_history_id,
            class_id=ctx.class_id,
            already_checked_in=False,
            chosen_plan_id=None,
            chosen_item_id=None,
            points_awarded=0,
            skip_reason=CheckinWarning.no_membership,
            memberships=[],
        )

    def side_effect(_ctx, member_id, _allow):
        if member_id == already_m:
            return already(member_id)
        if member_id == skipped_m:
            return skipped(member_id)
        return _recorded(ctx, member_id)

    service, _ = _service(ctx, side_effect)

    response, all_failed = await service.batch_checkin(
        ctx.class_id,
        ctx.gym_id,
        _OCCURRENCE_DATE,
        [recorded_m, already_m, skipped_m],
        False,
    )

    assert all_failed is False
    by_member = {r.member_id: r for r in response.results}

    checked_in = by_member[recorded_m]
    assert checked_in.status == BatchCheckinItemStatus.checked_in
    assert checked_in.points_awarded == ctx.points_worth
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
    ctx = _ctx()
    member = uuid4()

    def warned(_ctx, member_id, _is_member):
        return CheckinResponse(
            log_id=uuid4(),
            member_id=member_id,
            class_history_id=ctx.class_history_id,
            class_id=ctx.class_id,
            already_checked_in=False,
            chosen_plan_id=None,
            chosen_item_id=None,
            points_awarded=ctx.points_worth,
            skip_reason=None,
            warnings=[CheckinWarning.no_membership],
            memberships=[],
        )

    service, _ = _service(ctx, warned)

    response, all_failed = await service.batch_checkin(
        ctx.class_id, ctx.gym_id, _OCCURRENCE_DATE, [member], False
    )

    assert all_failed is False
    item = response.results[0]
    assert item.status == BatchCheckinItemStatus.checked_in
    assert item.warnings == [CheckinWarning.no_membership]
