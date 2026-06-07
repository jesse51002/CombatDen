"""Unit tests for the gated check-in selection logic.

These exercise the pure decision functions (no DB / no Stripe): plan
eligibility + capacity gating, the trial -> one_time -> recurring selection
priority, the auto-end-on-depletion rule, and the post-checkin usage
breakdown (including the renew_date / end_date pass-through).
"""

from datetime import date
from uuid import uuid4

from src.classes.schema.classes_cycle_counts_schema import MembershipUsage
from src.classes.schema.classes_plan_type import PlanType
from src.classes.service.checkin.classes_checkin_plan_selector import (
    build_breakdown,
    select_best_plan,
    should_end_membership,
)


def _usage(
    plan_id,
    plan_type: PlanType,
    class_count: int | None,
    classes_used: int,
    status: str = "active",
    renew_date: date | None = None,
    end_date: date | None = None,
) -> MembershipUsage:
    remaining = None if class_count is None else max(0, class_count - classes_used)
    return MembershipUsage(
        plan_id=plan_id,
        plan_type=plan_type,
        status=status,
        class_count=class_count,
        classes_used=classes_used,
        classes_remaining=remaining,
        renew_date=renew_date,
        end_date=end_date,
    )


# ── selection priority + gating ──────────────────────────────────────


def test_select_prefers_trial_over_recurring():
    """With both eligible and having capacity, trial wins over recurring."""
    trial = _usage(uuid4(), PlanType.trial, class_count=5, classes_used=0)
    recurring = _usage(uuid4(), PlanType.recurring, class_count=None, classes_used=0)
    eligible = {trial.plan_id, recurring.plan_id}

    chosen = select_best_plan([recurring, trial], eligible)
    assert chosen == trial.plan_id


def test_select_skips_ineligible_plan():
    """A plan not in the eligible set is never chosen even with capacity."""
    trial = _usage(uuid4(), PlanType.trial, class_count=5, classes_used=0)
    recurring = _usage(uuid4(), PlanType.recurring, class_count=None, classes_used=0)
    eligible = {recurring.plan_id}  # trial not eligible for this class

    chosen = select_best_plan([trial, recurring], eligible)
    assert chosen == recurring.plan_id


def test_select_skips_depleted_capacity():
    """A trial with no remaining capacity is skipped for the recurring plan."""
    depleted = _usage(uuid4(), PlanType.trial, class_count=3, classes_used=3)
    recurring = _usage(uuid4(), PlanType.recurring, class_count=None, classes_used=0)
    eligible = {depleted.plan_id, recurring.plan_id}

    chosen = select_best_plan([depleted, recurring], eligible)
    assert chosen == recurring.plan_id


def test_select_returns_none_when_nothing_qualifies():
    """No eligible plan with capacity -> hard gate (None)."""
    depleted = _usage(uuid4(), PlanType.one_time, class_count=1, classes_used=1)
    eligible = {depleted.plan_id}
    assert select_best_plan([depleted], eligible) is None


def test_select_orders_one_time_by_ascending_class_count():
    """Within a type, the lower class_count is consumed first."""
    small = _usage(uuid4(), PlanType.one_time, class_count=2, classes_used=0)
    big = _usage(uuid4(), PlanType.one_time, class_count=10, classes_used=0)
    eligible = {small.plan_id, big.plan_id}

    chosen = select_best_plan([big, small], eligible)
    assert chosen == small.plan_id


def test_unlimited_plan_always_has_capacity():
    """class_count=None means unlimited — always selectable."""
    unlimited = _usage(uuid4(), PlanType.recurring, class_count=None, classes_used=999)
    eligible = {unlimited.plan_id}
    assert select_best_plan([unlimited], eligible) == unlimited.plan_id


# ── auto-end on depletion ────────────────────────────────────────────


def test_should_end_trial_on_last_class():
    """A trial used to its final class auto-ends (used + 1 >= class_count)."""
    last = _usage(uuid4(), PlanType.trial, class_count=3, classes_used=2)
    assert should_end_membership(last) is True


def test_should_not_end_trial_with_capacity_left():
    last = _usage(uuid4(), PlanType.trial, class_count=5, classes_used=1)
    assert should_end_membership(last) is False


def test_recurring_never_auto_ends():
    rec = _usage(uuid4(), PlanType.recurring, class_count=None, classes_used=100)
    assert should_end_membership(rec) is False


def test_unlimited_one_time_never_auto_ends():
    unlimited = _usage(uuid4(), PlanType.one_time, class_count=None, classes_used=50)
    assert should_end_membership(unlimited) is False


# ── breakdown ────────────────────────────────────────────────────────


def test_breakdown_increments_chosen_plan_usage():
    """The charged plan's usage is +1 and remaining recomputed; eligibility flagged."""
    chosen = _usage(uuid4(), PlanType.one_time, class_count=5, classes_used=2)
    other = _usage(uuid4(), PlanType.recurring, class_count=None, classes_used=7)
    eligible = {chosen.plan_id}

    breakdown = build_breakdown([chosen, other], eligible, chosen.plan_id)
    by_plan = {b.plan_id: b for b in breakdown}

    assert by_plan[chosen.plan_id].classes_used == 3
    assert by_plan[chosen.plan_id].classes_remaining == 2
    assert by_plan[chosen.plan_id].is_eligible is True
    # The non-chosen plan is unchanged and flagged ineligible.
    assert by_plan[other.plan_id].classes_used == 7
    assert by_plan[other.plan_id].is_eligible is False


def test_breakdown_carries_renew_and_end_dates():
    """renew_date (recurring) and end_date (trial / one_time) pass through."""
    renews = _usage(
        uuid4(),
        PlanType.recurring,
        class_count=None,
        classes_used=0,
        renew_date=date(2026, 7, 1),
    )
    expires = _usage(
        uuid4(),
        PlanType.one_time,
        class_count=5,
        classes_used=0,
        end_date=date(2026, 8, 15),
    )
    eligible = {renews.plan_id, expires.plan_id}

    breakdown = build_breakdown([renews, expires], eligible, expires.plan_id)
    by_plan = {b.plan_id: b for b in breakdown}

    assert by_plan[renews.plan_id].renew_date == date(2026, 7, 1)
    assert by_plan[renews.plan_id].end_date is None
    assert by_plan[expires.plan_id].end_date == date(2026, 8, 15)
    assert by_plan[expires.plan_id].renew_date is None
