"""Unit tests for the unified check-in gate (no DB / no Stripe).

``CheckinMemberGate.checkin_member`` is driven against mocked collaborators
(``_queries`` / ``_writer`` / ``_cycle_counts``; the pure ``_plan_selector``
stays real). Covers the ``is_member`` block-vs-warn split:

* ``is_member=True`` (kiosk) — the strict gate: a clean covering membership is
  admitted (even when a higher-priority pack is depleted), while no membership /
  out of classes / ineligible plan / over capacity is rejected with the matching
  ``skip_reason`` and nothing is written.
* ``is_member=False`` (staff) — always records, attributing to the best
  available membership (NULL when none, over-drawing a depleted pack), with the
  blocking conditions returned as ``warnings``. Points are awarded on every new
  row (membership or not).
"""

from datetime import UTC, date, datetime
from unittest.mock import AsyncMock, MagicMock
from uuid import UUID, uuid4

from schema.membership_plan import PlanType

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.checkin.schema.checkin_schema import (
    CheckinWarning,
    OccurrenceContext,
)
from src.checkin.schema.cycle_counts_schema import (
    CheckinCycleCountsResponse,
    MembershipUsage,
    UserCycleCounts,
)
from src.checkin.service.checkin_member_gate import CheckinMemberGate


def _ctx(*, points_worth: int = 50, max_capacity: int | None = None) -> OccurrenceContext:
    return OccurrenceContext(
        class_history_id=uuid4(),
        class_id=uuid4(),
        gym_id=uuid4(),
        occurred_at=datetime(2026, 6, 1, 17, 0, tzinfo=UTC),
        points_worth=points_worth,
        class_name="Evening BJJ",
        max_capacity=max_capacity,
        allowed_plan_ids=None,
        instructor_id=None,
        duration_minutes=60,
    )


def _usage(
    plan_id: UUID,
    plan_type: PlanType,
    class_count: int | None,
    classes_used: int,
    *,
    item_id: UUID | None = None,
    start_date: date | None = None,
) -> MembershipUsage:
    remaining = None if class_count is None else max(0, class_count - classes_used)
    return MembershipUsage(
        item_id=item_id or uuid4(),
        plan_id=plan_id,
        start_date=start_date or date(2024, 1, 1),
        plan_type=plan_type,
        status="active",
        class_count=class_count,
        classes_used=classes_used,
        classes_remaining=remaining,
        renew_date=None,
        end_date=None,
    )


def _gate(
    *,
    memberships: list[MembershipUsage],
    eligible: set[UUID],
    attendance_count: int = 0,
    existing: dict | None = None,
    log_id: UUID | None = None,
) -> tuple[CheckinMemberGate, AsyncMock]:
    """A gate with mocked queries / writer / cycle-counts; pure selector kept.

    ``write_checkin`` returns ``(log_id, already=False, points=ctx.points_worth)``
    — but the caller passes ``ctx.points_worth`` when it asserts points, so the
    mock just echoes a fixed points value via side effect below.
    """
    member_id = uuid4()
    gate = CheckinMemberGate(db_pool=MagicMock(), cycle_counts_service=MagicMock())

    gate._queries = MagicMock()
    gate._queries.get_existing_attendance = AsyncMock(return_value=existing)
    gate._queries.get_eligible_plans = AsyncMock(return_value=eligible)
    gate._queries.count_attendance = AsyncMock(return_value=attendance_count)

    gate._cycle_counts = MagicMock()
    gate._cycle_counts.get_cycle_counts = AsyncMock(
        return_value=CheckinCycleCountsResponse(
            users=(
                [UserCycleCounts(member_id=member_id, memberships=memberships)]
                if memberships
                else []
            )
        )
    )

    writer = AsyncMock(return_value=(log_id or uuid4(), False, 50))
    gate._writer = MagicMock()
    gate._writer.write_checkin = writer
    return gate, writer


# ── staff (is_member=False): always records ──────────────────────────


async def test_staff_clean_covered_records_no_warnings() -> None:
    """A covered staff check-in records, attributes to the plan, no warnings."""
    plan = uuid4()
    m = _usage(plan, PlanType.recurring, class_count=None, classes_used=3)
    gate, writer = _gate(memberships=[m], eligible={plan})

    res = await gate.checkin_member(_ctx(), uuid4(), is_member=False)

    assert res.log_id is not None
    assert res.chosen_plan_id == plan
    assert res.chosen_item_id == m.item_id
    assert res.warnings == []
    assert res.points_awarded == 50
    writer.assert_awaited_once()
    _, _, plan_arg, item_arg, should_end = writer.await_args.args
    assert plan_arg == plan and item_arg == m.item_id and should_end is False


async def test_staff_no_membership_records_null_attribution_and_warns() -> None:
    """No membership: records with NULL plan/item, no_membership warning, points
    still awarded."""
    gate, writer = _gate(memberships=[], eligible=set())

    res = await gate.checkin_member(_ctx(), uuid4(), is_member=False)

    assert res.log_id is not None
    assert res.chosen_plan_id is None
    assert res.chosen_item_id is None
    assert res.warnings == [CheckinWarning.no_membership]
    assert res.points_awarded == 50
    writer.assert_awaited_once()
    _, _, plan_arg, item_arg, should_end = writer.await_args.args
    assert plan_arg is None and item_arg is None and should_end is False
    assert res.memberships == []


async def test_staff_out_of_classes_overdraws_and_warns() -> None:
    """A depleted eligible pack is over-drawn (should_end True) with an
    out_of_classes warning."""
    plan = uuid4()
    pack = _usage(plan, PlanType.one_time, class_count=5, classes_used=5)
    gate, writer = _gate(memberships=[pack], eligible={plan})

    res = await gate.checkin_member(_ctx(), uuid4(), is_member=False)

    assert res.chosen_item_id == pack.item_id
    assert res.warnings == [CheckinWarning.out_of_classes]
    _, _, _, _, should_end = writer.await_args.args
    assert should_end is True  # over-draw re-ends the depleted pack


async def test_staff_ineligible_plan_records_and_warns() -> None:
    """An ineligible membership is attributed with an ineligible_plan warning."""
    plan = uuid4()
    m = _usage(plan, PlanType.recurring, class_count=None, classes_used=0)
    gate, _ = _gate(memberships=[m], eligible=set())  # plan not eligible

    res = await gate.checkin_member(_ctx(), uuid4(), is_member=False)

    assert res.chosen_plan_id == plan
    assert res.warnings == [CheckinWarning.ineligible_plan]


async def test_staff_over_capacity_records_and_warns() -> None:
    """A full room warns but still records for staff."""
    plan = uuid4()
    m = _usage(plan, PlanType.recurring, class_count=None, classes_used=0)
    gate, writer = _gate(
        memberships=[m], eligible={plan}, attendance_count=10
    )

    res = await gate.checkin_member(
        _ctx(max_capacity=5), uuid4(), is_member=False
    )

    assert res.log_id is not None
    assert res.warnings == [CheckinWarning.over_capacity]
    writer.assert_awaited_once()


async def test_staff_combined_warnings_sorted_by_priority() -> None:
    """A depleted ineligible pack surfaces both reasons, priority-ordered."""
    plan = uuid4()
    pack = _usage(plan, PlanType.one_time, class_count=3, classes_used=3)
    gate, _ = _gate(memberships=[pack], eligible=set())  # ineligible + depleted

    res = await gate.checkin_member(_ctx(), uuid4(), is_member=False)

    assert res.warnings == [
        CheckinWarning.out_of_classes,
        CheckinWarning.ineligible_plan,
    ]


# ── kiosk (is_member=True): strict gate ──────────────────────────────


async def test_kiosk_clean_covered_records() -> None:
    plan = uuid4()
    m = _usage(plan, PlanType.recurring, class_count=None, classes_used=0)
    gate, writer = _gate(memberships=[m], eligible={plan})

    res = await gate.checkin_member(_ctx(), uuid4(), is_member=True)

    assert res.log_id is not None
    assert res.chosen_plan_id == plan
    assert res.skip_reason is None
    assert res.warnings == []
    writer.assert_awaited_once()


async def test_kiosk_no_membership_is_rejected() -> None:
    gate, writer = _gate(memberships=[], eligible=set())

    res = await gate.checkin_member(_ctx(), uuid4(), is_member=True)

    assert res.log_id is None
    assert res.skip_reason == CheckinWarning.no_membership
    assert res.points_awarded == 0
    writer.assert_not_awaited()


async def test_kiosk_out_of_classes_is_rejected() -> None:
    plan = uuid4()
    pack = _usage(plan, PlanType.one_time, class_count=5, classes_used=5)
    gate, writer = _gate(memberships=[pack], eligible={plan})

    res = await gate.checkin_member(_ctx(), uuid4(), is_member=True)

    assert res.log_id is None
    assert res.skip_reason == CheckinWarning.out_of_classes
    writer.assert_not_awaited()


async def test_kiosk_ineligible_plan_is_rejected() -> None:
    plan = uuid4()
    m = _usage(plan, PlanType.recurring, class_count=None, classes_used=0)
    gate, writer = _gate(memberships=[m], eligible=set())

    res = await gate.checkin_member(_ctx(), uuid4(), is_member=True)

    assert res.log_id is None
    assert res.skip_reason == CheckinWarning.ineligible_plan
    writer.assert_not_awaited()


async def test_kiosk_over_capacity_blocks_even_when_covered() -> None:
    plan = uuid4()
    m = _usage(plan, PlanType.recurring, class_count=None, classes_used=0)
    gate, writer = _gate(
        memberships=[m], eligible={plan}, attendance_count=5
    )

    res = await gate.checkin_member(
        _ctx(max_capacity=5), uuid4(), is_member=True
    )

    assert res.log_id is None
    assert res.skip_reason == CheckinWarning.over_capacity
    writer.assert_not_awaited()


async def test_kiosk_admits_when_a_clean_membership_covers_despite_depleted_pack() -> None:
    """The divergence case: a depleted higher-priority pack would warn a staff
    check-in, but the kiosk gate admits because a clean covering membership
    exists — and attributes to that clean (strict) membership."""
    pack_plan, rec_plan = uuid4(), uuid4()
    depleted = _usage(pack_plan, PlanType.trial, class_count=3, classes_used=3)
    covering = _usage(rec_plan, PlanType.recurring, class_count=None, classes_used=0)
    gate, writer = _gate(
        memberships=[depleted, covering], eligible={pack_plan, rec_plan}
    )

    res = await gate.checkin_member(_ctx(), uuid4(), is_member=True)

    assert res.log_id is not None
    assert res.skip_reason is None
    # Attributed to the clean recurring membership, not the depleted trial.
    assert res.chosen_plan_id == rec_plan
    assert res.chosen_item_id == covering.item_id


async def test_staff_overdraws_depleted_pack_even_when_a_clean_membership_covers() -> None:
    """Same shape, staff mode: forced selection over-draws the depleted trial
    (priority 0) and warns out_of_classes — the documented divergence."""
    pack_plan, rec_plan = uuid4(), uuid4()
    depleted = _usage(pack_plan, PlanType.trial, class_count=3, classes_used=3)
    covering = _usage(rec_plan, PlanType.recurring, class_count=None, classes_used=0)
    gate, _ = _gate(
        memberships=[depleted, covering], eligible={pack_plan, rec_plan}
    )

    res = await gate.checkin_member(_ctx(), uuid4(), is_member=False)

    assert res.chosen_plan_id == pack_plan
    assert res.warnings == [CheckinWarning.out_of_classes]


# ── idempotency (both modes) ─────────────────────────────────────────


async def test_existing_attendance_is_idempotent_repeat() -> None:
    """An existing row short-circuits to already_checked_in without writing."""
    plan, item = uuid4(), uuid4()
    log_id = uuid4()
    gate, writer = _gate(
        memberships=[],
        eligible=set(),
        existing={"log_id": log_id, "plan_id": plan, "item_id": item},
    )

    res = await gate.checkin_member(_ctx(), uuid4(), is_member=False)

    assert res.already_checked_in is True
    assert res.log_id == log_id
    assert res.chosen_plan_id == plan
    assert res.points_awarded == 0
    writer.assert_not_awaited()
