"""Unit tests for the unified check-in gate (no DB / no Stripe).

``CheckinMemberGate.checkin_member`` is driven against mocked collaborators
(``_queries`` / ``_writer`` / ``_cycle_counts``; the pure ``_plan_selector``
stays real). Covers the ``is_member`` block-vs-warn split:

* ``is_member=True`` (kiosk) — the strict gate: a clean covering membership is
  admitted (even when a higher-priority pack is depleted), while no membership /
  out of classes / ineligible plan / over capacity is rejected with the matching
  ``skip_reason`` and nothing is written.
* ``is_member=False`` (staff) — a clean check-in records; any blocking condition
  holds it for confirmation (``requires_confirmation``, nothing written) with the
  reasons as ``warnings``, UNLESS ``ignore_warnings`` overrides — which records,
  attributing to the best available membership (NULL when none, over-drawing a
  depleted pack). Points are awarded on every new row (membership or not).
"""

from datetime import UTC, date, datetime, time
from unittest.mock import AsyncMock, MagicMock
from uuid import UUID, uuid4

from schema.membership_plan import PlanType

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.checkin.schema.checkin_schema import (
    CheckinWarning,
    ResolvedClass,
)
from src.checkin.schema.cycle_counts_schema import (
    CheckinCycleCountsResponse,
    MembershipUsage,
    UserCycleCounts,
)
from src.checkin.service.checkin_member_gate import CheckinMemberGate


def _resolved_class(*, points_worth: int = 50, max_capacity: int | None = None) -> ResolvedClass:
    return ResolvedClass(
        class_id=uuid4(),
        gym_id=uuid4(),
        occurrence_date=date(2026, 6, 1),
        original_time=time(17, 0),
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
    unsigned_waivers: list[dict] | None = None,
) -> tuple[CheckinMemberGate, AsyncMock]:
    """A gate with mocked queries / writer / cycle-counts; pure selector kept.

    ``write_checkin`` returns ``(log_id, already=False, points=resolved_class.points_worth)``
    — but the caller passes ``resolved_class.points_worth`` when it asserts points, so the
    mock just echoes a fixed points value via side effect below.
    """
    member_id = uuid4()
    gate = CheckinMemberGate(db_pool=MagicMock(), cycle_counts_service=MagicMock())

    gate._queries = MagicMock()
    gate._queries.get_existing_attendance = AsyncMock(return_value=existing)
    gate._queries.get_eligible_plans = AsyncMock(return_value=eligible)
    # A set of ``attendance_count`` OTHER members already signed-up-or-attended
    # (never the member under test) -- the gate's capacity check is len(set)
    # vs max_capacity, skipped entirely when the tested member is already in
    # the set (covered by its own dedicated tests below).
    gate._queries.get_signup_or_attended_members = AsyncMock(
        return_value={uuid4() for _ in range(attendance_count)}
    )
    # The waiver gate: default fully signed (empty). Pass rows to simulate a
    # required-but-unsigned waiver.
    gate._queries.get_unsigned_waivers = AsyncMock(
        return_value=unsigned_waivers or []
    )

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


# ── staff (is_member=False): clean records; a warning needs confirmation ──


async def test_staff_clean_covered_records_no_warnings() -> None:
    """A covered staff check-in records, attributes to the plan, no warnings."""
    plan = uuid4()
    m = _usage(plan, PlanType.recurring, class_count=None, classes_used=3)
    gate, writer = _gate(memberships=[m], eligible={plan})

    res = await gate.checkin_member(_resolved_class(), uuid4(), is_member=False)

    assert res.log_id is not None
    assert res.chosen_plan_id == plan
    assert res.chosen_item_id == m.item_id
    assert res.warnings == []
    assert res.points_awarded == 50
    writer.assert_awaited_once()
    _, _, plan_arg, item_arg, should_end = writer.await_args.args
    assert plan_arg == plan and item_arg == m.item_id and should_end is False


async def test_staff_no_membership_needs_confirmation() -> None:
    """No membership: NOT recorded — requires_confirmation with a no_membership
    warning, nothing written."""
    gate, writer = _gate(memberships=[], eligible=set())

    res = await gate.checkin_member(_resolved_class(), uuid4(), is_member=False)

    assert res.requires_confirmation is True
    assert res.log_id is None
    assert res.chosen_plan_id is None
    assert res.chosen_item_id is None
    assert res.warnings == [CheckinWarning.no_membership]
    assert res.points_awarded == 0
    assert res.memberships == []
    writer.assert_not_awaited()


async def test_staff_no_membership_override_records_null_attribution() -> None:
    """ignore_warnings overrides: records with NULL plan/item, the warning
    surfaced, points awarded."""
    gate, writer = _gate(memberships=[], eligible=set())

    res = await gate.checkin_member(
        _resolved_class(), uuid4(), is_member=False, ignore_warnings=True
    )

    assert res.log_id is not None
    assert res.chosen_plan_id is None
    assert res.chosen_item_id is None
    assert res.warnings == [CheckinWarning.no_membership]
    assert res.points_awarded == 50
    writer.assert_awaited_once()
    _, _, plan_arg, item_arg, should_end = writer.await_args.args
    assert plan_arg is None and item_arg is None and should_end is False


async def test_staff_out_of_classes_needs_confirmation() -> None:
    """A depleted eligible pack is held for confirmation, not over-drawn."""
    plan = uuid4()
    pack = _usage(plan, PlanType.one_time, class_count=5, classes_used=5)
    gate, writer = _gate(memberships=[pack], eligible={plan})

    res = await gate.checkin_member(_resolved_class(), uuid4(), is_member=False)

    assert res.requires_confirmation is True
    assert res.log_id is None
    assert res.warnings == [CheckinWarning.out_of_classes]
    writer.assert_not_awaited()


async def test_staff_out_of_classes_override_overdraws() -> None:
    """ignore_warnings over-draws the depleted pack (should_end True)."""
    plan = uuid4()
    pack = _usage(plan, PlanType.one_time, class_count=5, classes_used=5)
    gate, writer = _gate(memberships=[pack], eligible={plan})

    res = await gate.checkin_member(
        _resolved_class(), uuid4(), is_member=False, ignore_warnings=True
    )

    assert res.chosen_item_id == pack.item_id
    assert res.warnings == [CheckinWarning.out_of_classes]
    _, _, _, _, should_end = writer.await_args.args
    assert should_end is True  # over-draw re-ends the depleted pack


async def test_staff_ineligible_plan_needs_confirmation() -> None:
    """An ineligible membership is held for confirmation."""
    plan = uuid4()
    m = _usage(plan, PlanType.recurring, class_count=None, classes_used=0)
    gate, writer = _gate(memberships=[m], eligible=set())  # plan not eligible

    res = await gate.checkin_member(_resolved_class(), uuid4(), is_member=False)

    assert res.requires_confirmation is True
    assert res.log_id is None
    assert res.warnings == [CheckinWarning.ineligible_plan]
    writer.assert_not_awaited()


async def test_staff_ineligible_plan_override_records() -> None:
    """ignore_warnings records, attributing the ineligible membership."""
    plan = uuid4()
    m = _usage(plan, PlanType.recurring, class_count=None, classes_used=0)
    gate, _ = _gate(memberships=[m], eligible=set())

    res = await gate.checkin_member(
        _resolved_class(), uuid4(), is_member=False, ignore_warnings=True
    )

    assert res.chosen_plan_id == plan
    assert res.warnings == [CheckinWarning.ineligible_plan]


async def test_staff_over_capacity_needs_confirmation() -> None:
    """A full room is held for confirmation for staff."""
    plan = uuid4()
    m = _usage(plan, PlanType.recurring, class_count=None, classes_used=0)
    gate, writer = _gate(
        memberships=[m], eligible={plan}, attendance_count=10
    )

    res = await gate.checkin_member(
        _resolved_class(max_capacity=5), uuid4(), is_member=False
    )

    assert res.requires_confirmation is True
    assert res.log_id is None
    assert res.warnings == [CheckinWarning.over_capacity]
    writer.assert_not_awaited()


async def test_staff_over_capacity_override_records() -> None:
    """ignore_warnings records into the full room."""
    plan = uuid4()
    m = _usage(plan, PlanType.recurring, class_count=None, classes_used=0)
    gate, writer = _gate(
        memberships=[m], eligible={plan}, attendance_count=10
    )

    res = await gate.checkin_member(
        _resolved_class(max_capacity=5), uuid4(), is_member=False, ignore_warnings=True
    )

    assert res.log_id is not None
    assert res.warnings == [CheckinWarning.over_capacity]
    writer.assert_awaited_once()


async def test_staff_combined_warnings_sorted_by_priority() -> None:
    """A depleted ineligible pack surfaces both reasons, priority-ordered, held
    for confirmation."""
    plan = uuid4()
    pack = _usage(plan, PlanType.one_time, class_count=3, classes_used=3)
    gate, _ = _gate(memberships=[pack], eligible=set())  # ineligible + depleted

    res = await gate.checkin_member(_resolved_class(), uuid4(), is_member=False)

    assert res.requires_confirmation is True
    assert res.warnings == [
        CheckinWarning.out_of_classes,
        CheckinWarning.ineligible_plan,
    ]


# ── kiosk (is_member=True): strict gate ──────────────────────────────


async def test_kiosk_clean_covered_records() -> None:
    plan = uuid4()
    m = _usage(plan, PlanType.recurring, class_count=None, classes_used=0)
    gate, writer = _gate(memberships=[m], eligible={plan})

    res = await gate.checkin_member(_resolved_class(), uuid4(), is_member=True)

    assert res.log_id is not None
    assert res.chosen_plan_id == plan
    assert res.skip_reason is None
    assert res.warnings == []
    writer.assert_awaited_once()


async def test_kiosk_no_membership_is_rejected() -> None:
    gate, writer = _gate(memberships=[], eligible=set())

    res = await gate.checkin_member(_resolved_class(), uuid4(), is_member=True)

    assert res.log_id is None
    assert res.skip_reason == CheckinWarning.no_membership
    assert res.points_awarded == 0
    writer.assert_not_awaited()


async def test_kiosk_out_of_classes_is_rejected() -> None:
    plan = uuid4()
    pack = _usage(plan, PlanType.one_time, class_count=5, classes_used=5)
    gate, writer = _gate(memberships=[pack], eligible={plan})

    res = await gate.checkin_member(_resolved_class(), uuid4(), is_member=True)

    assert res.log_id is None
    assert res.skip_reason == CheckinWarning.out_of_classes
    writer.assert_not_awaited()


async def test_kiosk_ineligible_plan_is_rejected() -> None:
    plan = uuid4()
    m = _usage(plan, PlanType.recurring, class_count=None, classes_used=0)
    gate, writer = _gate(memberships=[m], eligible=set())

    res = await gate.checkin_member(_resolved_class(), uuid4(), is_member=True)

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
        _resolved_class(max_capacity=5), uuid4(), is_member=True
    )

    assert res.log_id is None
    assert res.skip_reason == CheckinWarning.over_capacity
    writer.assert_not_awaited()


async def test_unlimited_capacity_never_queries_the_union() -> None:
    """max_capacity=None (unlimited) -> the capacity gate short-circuits
    before even querying the signed-up-or-attended union -- always admitted,
    kiosk or staff."""
    plan = uuid4()
    m = _usage(plan, PlanType.recurring, class_count=None, classes_used=0)
    gate, writer = _gate(memberships=[m], eligible={plan})

    res = await gate.checkin_member(
        _resolved_class(max_capacity=None), uuid4(), is_member=True
    )

    assert res.log_id is not None
    assert res.skip_reason is None
    gate._queries.get_signup_or_attended_members.assert_not_awaited()


async def test_staff_admits_when_already_in_the_signed_up_or_attended_union() -> None:
    """The same union-membership capacity skip applies to a staff check-in:
    a member already counted (a prior sign-up, or an idempotent repeat) is
    recorded cleanly with no warnings even when the room is nominally full --
    ``_is_over_capacity`` is evaluated once, shared by both modes."""
    plan = uuid4()
    m = _usage(plan, PlanType.recurring, class_count=None, classes_used=0)
    member_id = uuid4()
    gate, writer = _gate(memberships=[m], eligible={plan})
    # The room is at capacity (3/3) but this member is already one of the 3.
    gate._queries.get_signup_or_attended_members = AsyncMock(
        return_value={member_id, uuid4(), uuid4()}
    )

    res = await gate.checkin_member(
        _resolved_class(max_capacity=3), member_id, is_member=False
    )

    assert res.log_id is not None
    assert res.requires_confirmation is False
    assert res.warnings == []
    writer.assert_awaited_once()


async def test_kiosk_admits_when_already_in_the_signed_up_or_attended_union() -> None:
    """A member already counted in the union (e.g. a prior sign-up) is
    admitted even when the room is nominally full -- the capacity gate skips
    a member who is already part of the count."""
    plan = uuid4()
    m = _usage(plan, PlanType.recurring, class_count=None, classes_used=0)
    member_id = uuid4()
    gate, writer = _gate(memberships=[m], eligible={plan})
    # The room is at capacity (3/3) but this member is already one of the 3.
    gate._queries.get_signup_or_attended_members = AsyncMock(
        return_value={member_id, uuid4(), uuid4()}
    )

    res = await gate.checkin_member(
        _resolved_class(max_capacity=3), member_id, is_member=True
    )

    assert res.log_id is not None
    assert res.skip_reason is None
    writer.assert_awaited_once()


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

    res = await gate.checkin_member(_resolved_class(), uuid4(), is_member=True)

    assert res.log_id is not None
    assert res.skip_reason is None
    # Attributed to the clean recurring membership, not the depleted trial.
    assert res.chosen_plan_id == rec_plan
    assert res.chosen_item_id == covering.item_id


async def test_staff_override_overdraws_depleted_pack_over_clean_membership() -> None:
    """Same shape, staff override: forced selection over-draws the depleted trial
    (priority 0) and warns out_of_classes — the documented divergence."""
    pack_plan, rec_plan = uuid4(), uuid4()
    depleted = _usage(pack_plan, PlanType.trial, class_count=3, classes_used=3)
    covering = _usage(rec_plan, PlanType.recurring, class_count=None, classes_used=0)
    gate, _ = _gate(
        memberships=[depleted, covering], eligible={pack_plan, rec_plan}
    )

    res = await gate.checkin_member(
        _resolved_class(), uuid4(), is_member=False, ignore_warnings=True
    )

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

    resolved_class = _resolved_class()
    res = await gate.checkin_member(resolved_class, uuid4(), is_member=False)

    assert res.already_checked_in is True
    assert res.log_id == log_id
    assert res.chosen_plan_id == plan
    # The repeat echoes the class's points (already in the balance), not 0.
    assert res.points_awarded == resolved_class.points_worth
    writer.assert_not_awaited()


# ── the waiver gate: unsigned required waiver blocks kiosk, warns staff ──


def _unsigned_row() -> dict:
    return {"waiver_id": uuid4(), "name": "Liability Waiver"}


async def test_kiosk_unsigned_waiver_rejected() -> None:
    """A kiosk check-in with an unsigned required waiver is rejected — even
    with a clean covering membership — and nothing is written."""
    plan = uuid4()
    m = _usage(plan, PlanType.recurring, class_count=None, classes_used=0)
    gate, writer = _gate(
        memberships=[m],
        eligible={plan},
        unsigned_waivers=[_unsigned_row()],
    )

    res = await gate.checkin_member(_resolved_class(), uuid4(), is_member=True)

    assert res.log_id is None
    assert res.skip_reason == CheckinWarning.unsigned_waiver
    assert res.points_awarded == 0
    writer.assert_not_awaited()


async def test_staff_unsigned_waiver_needs_confirmation() -> None:
    """A staff check-in with an unsigned waiver is held for confirmation —
    the pop-up path: nothing written, the warning returned."""
    plan = uuid4()
    m = _usage(plan, PlanType.recurring, class_count=None, classes_used=0)
    gate, writer = _gate(
        memberships=[m],
        eligible={plan},
        unsigned_waivers=[_unsigned_row()],
    )

    res = await gate.checkin_member(_resolved_class(), uuid4(), is_member=False)

    assert res.requires_confirmation is True
    assert res.log_id is None
    assert CheckinWarning.unsigned_waiver in res.warnings
    writer.assert_not_awaited()


async def test_staff_unsigned_waiver_override_records() -> None:
    """``ignore_warnings`` records through the unsigned-waiver warning,
    attributing normally and echoing the warning on the recorded response."""
    plan = uuid4()
    m = _usage(plan, PlanType.recurring, class_count=None, classes_used=0)
    gate, writer = _gate(
        memberships=[m],
        eligible={plan},
        unsigned_waivers=[_unsigned_row()],
    )

    res = await gate.checkin_member(
        _resolved_class(), uuid4(), is_member=False, ignore_warnings=True
    )

    assert res.log_id is not None
    assert res.chosen_plan_id == plan
    assert CheckinWarning.unsigned_waiver in res.warnings
    writer.assert_awaited_once()


async def test_unsigned_waiver_flagged_even_without_coverage() -> None:
    """The waiver gate is membership-independent: with no covering
    membership, BOTH no_membership and unsigned_waiver come back."""
    gate, writer = _gate(
        memberships=[],
        eligible=set(),
        unsigned_waivers=[_unsigned_row()],
    )

    res = await gate.checkin_member(_resolved_class(), uuid4(), is_member=False)

    assert res.requires_confirmation is True
    assert CheckinWarning.no_membership in res.warnings
    assert CheckinWarning.unsigned_waiver in res.warnings
    writer.assert_not_awaited()
