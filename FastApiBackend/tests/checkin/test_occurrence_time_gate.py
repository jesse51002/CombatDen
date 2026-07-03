"""The occurrence-time-aware membership gate (retro check-ins).

Coverage is evaluated at the OCCURRENCE'S instant, never at now:
``CheckinMemberGate`` passes ``resolved_class.occurred_at`` into the cycle
counts read and filters candidates on ``covers_reference`` — so an
ended-as-of-now trial that covered the class still attributes, while a
membership that didn't cover it (started later / already terminated by then)
is excluded even when it's active today. Plus the pure window/period math on
``CycleCountsService`` and the reverser's duration-derived un-end target.
"""

from datetime import UTC, date, datetime, time
from unittest.mock import AsyncMock, MagicMock
from uuid import uuid4

from dateutil.relativedelta import relativedelta
from schema.membership_plan import PlanType

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.checkin.schema.checkin_schema import CheckinWarning, ResolvedClass
from src.checkin.schema.cycle_counts_schema import (
    CheckinCycleCountsResponse,
    MembershipUsage,
    UserCycleCounts,
)
from src.checkin.service.checkin_member_gate import CheckinMemberGate
from src.checkin.service.checkin_reverser import CheckinReverser
from src.checkin.service.cycle_counts_service import CycleCountsService

_OCCURRED_AT = datetime(2026, 6, 20, 18, 0, tzinfo=UTC)


def _resolved() -> ResolvedClass:
    return ResolvedClass(
        class_id=uuid4(),
        gym_id=uuid4(),
        occurrence_date=date(2026, 6, 20),
        original_time=time(18, 0),
        occurred_at=_OCCURRED_AT,
        points_worth=50,
        class_name="Retro BJJ",
        max_capacity=None,
        allowed_plan_ids=None,
        instructor_id=None,
        duration_minutes=60,
    )


def _usage(
    *,
    status: str = "active",
    covers_reference: bool = True,
    plan_type: PlanType = PlanType.trial,
) -> MembershipUsage:
    return MembershipUsage(
        item_id=uuid4(),
        plan_id=uuid4(),
        start_date=date(2026, 6, 1),
        plan_type=plan_type,
        status=status,
        covers_reference=covers_reference,
        class_count=10,
        classes_used=1,
        classes_remaining=9,
        renew_date=None,
        end_date=None,
    )


def _gate(memberships: list[MembershipUsage]) -> CheckinMemberGate:
    gate = CheckinMemberGate(
        db_pool=MagicMock(), cycle_counts_service=MagicMock()
    )
    gate._queries = MagicMock()
    gate._queries.get_existing_attendance = AsyncMock(return_value=None)
    gate._queries.get_eligible_plans = AsyncMock(
        return_value={m.plan_id for m in memberships}
    )
    gate._queries.get_signup_or_attended_members = AsyncMock(
        return_value=set()
    )
    # The waiver gate: fully signed (these tests cover occurrence timing).
    gate._queries.get_unsigned_waivers = AsyncMock(return_value=[])
    gate._cycle_counts = MagicMock()
    gate._cycle_counts.get_cycle_counts = AsyncMock(
        return_value=CheckinCycleCountsResponse(
            users=(
                [
                    UserCycleCounts(
                        member_id=uuid4(), memberships=memberships
                    )
                ]
                if memberships
                else []
            )
        )
    )
    gate._writer = MagicMock()
    gate._writer.write_checkin = AsyncMock(
        return_value=(uuid4(), False, 50)
    )
    return gate


async def test_gate_evaluates_at_the_occurrence_instant() -> None:
    """The cycle-counts read receives the occurrence's effective start."""
    gate = _gate([_usage()])
    await gate.checkin_member(_resolved(), uuid4())
    kwargs = gate._cycle_counts.get_cycle_counts.call_args.kwargs
    assert kwargs["reference_instant"] == _OCCURRED_AT


async def test_ended_now_trial_that_covered_the_occurrence_attributes() -> None:
    """A trial that has since ENDED still covers a class inside its window:
    the retro staff check-in is clean and attributes to it (no
    no_membership warning, no NULL attribution)."""
    covering = _usage(status="ended", covers_reference=True)
    gate = _gate([covering])
    response = await gate.checkin_member(_resolved(), uuid4())
    assert response.log_id is not None
    assert response.warnings == []
    assert response.chosen_item_id == covering.item_id


async def test_membership_not_covering_the_occurrence_is_no_membership() -> None:
    """A membership that did NOT cover the occurrence (started after it /
    terminated before it) is excluded even while active today — the retro
    check-in warns no_membership instead of misattributing."""
    not_covering = _usage(status="active", covers_reference=False)
    gate = _gate([not_covering])
    response = await gate.checkin_member(_resolved(), uuid4())
    assert response.requires_confirmation is True
    assert CheckinWarning.no_membership in response.warnings


# ── the cycle-window math ────────────────────────────────────────────────


def test_containing_window_steps_back_by_months() -> None:
    ws, we = CycleCountsService._containing_window(
        date(2026, 6, 15), relativedelta(months=1), date(2026, 3, 20)
    )
    assert (ws, we) == (date(2026, 3, 15), date(2026, 4, 15))


def test_containing_window_lands_on_boundary() -> None:
    """A reference ON a window start belongs to that window."""
    ws, we = CycleCountsService._containing_window(
        date(2026, 6, 15), relativedelta(months=1), date(2026, 5, 15)
    )
    assert (ws, we) == (date(2026, 5, 15), date(2026, 6, 15))


def test_plan_period_units() -> None:
    assert CycleCountsService._plan_period(2, "week") == relativedelta(
        weeks=2
    )
    assert CycleCountsService._plan_period(1, "month") == relativedelta(
        months=1
    )
    assert CycleCountsService._plan_period(1, "year") == relativedelta(
        years=1
    )
    assert CycleCountsService._plan_period(None, None) is None


# ── the un-end restore target ────────────────────────────────────────────


def test_duration_end_date_restores_purchase_expiry() -> None:
    """The un-end restores start_date + the plan's duration — the same
    derivation the purchase stamped — so removing an attendance from a
    duration pack never erases its natural expiry."""
    info = {
        "start_date": date(2026, 1, 31),
        "duration_amount": 1,
        "duration_unit": "month",
    }
    assert CheckinReverser._duration_end_date(info) == date(2026, 2, 28)


def test_duration_end_date_none_for_pure_count_pack() -> None:
    info = {
        "start_date": date(2026, 1, 1),
        "duration_amount": None,
        "duration_unit": None,
    }
    assert CheckinReverser._duration_end_date(info) is None
