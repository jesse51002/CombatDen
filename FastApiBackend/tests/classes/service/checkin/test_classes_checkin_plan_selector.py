"""Unit tests for the gated check-in selection logic.

These exercise the pure decision functions (no DB / no Stripe): plan
eligibility + capacity gating, the trial -> one_time -> recurring selection
priority, the oldest-pack-first tiebreaker that drains two packs on the same
plan one at a time, the auto-end-on-depletion rule, and the post-checkin usage
breakdown (including the renew_date / end_date pass-through).
"""

from datetime import date
from uuid import uuid4

from schema.membership_plan import PlanType

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.classes.schema.classes_cycle_counts_schema import MembershipUsage
from src.classes.service.checkin.classes_checkin_plan_selector import (
    build_breakdown,
    select_best_membership,
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
    item_id=None,
    start_date: date | None = None,
) -> MembershipUsage:
    remaining = None if class_count is None else max(0, class_count - classes_used)
    return MembershipUsage(
        item_id=item_id or uuid4(),
        plan_id=plan_id,
        start_date=start_date or date(2024, 1, 1),
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

    chosen = select_best_membership([recurring, trial], eligible)
    assert chosen is trial


def test_select_prefers_one_time_over_recurring():
    """A limited one_time pack drains before the unlimited recurring plan.

    The recurring plan always has capacity, so if it ranked first a member's
    paid pack would never get consumed — limited packs must win.
    """
    pack = _usage(uuid4(), PlanType.one_time, class_count=10, classes_used=0)
    recurring = _usage(
        uuid4(), PlanType.recurring, class_count=None, classes_used=0,
    )
    eligible = {pack.plan_id, recurring.plan_id}

    chosen = select_best_membership([recurring, pack], eligible)
    assert chosen is pack


def test_select_skips_ineligible_plan():
    """A plan not in the eligible set is never chosen even with capacity."""
    trial = _usage(uuid4(), PlanType.trial, class_count=5, classes_used=0)
    recurring = _usage(uuid4(), PlanType.recurring, class_count=None, classes_used=0)
    eligible = {recurring.plan_id}  # trial not eligible for this class

    chosen = select_best_membership([trial, recurring], eligible)
    assert chosen is recurring


def test_select_skips_depleted_capacity():
    """A trial with no remaining capacity is skipped for the recurring plan."""
    depleted = _usage(uuid4(), PlanType.trial, class_count=3, classes_used=3)
    recurring = _usage(uuid4(), PlanType.recurring, class_count=None, classes_used=0)
    eligible = {depleted.plan_id, recurring.plan_id}

    chosen = select_best_membership([depleted, recurring], eligible)
    assert chosen is recurring


def test_select_returns_none_when_nothing_qualifies():
    """No eligible plan with capacity -> hard gate (None)."""
    depleted = _usage(uuid4(), PlanType.one_time, class_count=1, classes_used=1)
    eligible = {depleted.plan_id}
    assert select_best_membership([depleted], eligible) is None


def test_select_orders_one_time_by_ascending_class_count():
    """Within a type, the lower class_count is consumed first."""
    small = _usage(uuid4(), PlanType.one_time, class_count=2, classes_used=0)
    big = _usage(uuid4(), PlanType.one_time, class_count=10, classes_used=0)
    eligible = {small.plan_id, big.plan_id}

    chosen = select_best_membership([big, small], eligible)
    assert chosen is small


def test_unlimited_plan_always_has_capacity():
    """class_count=None means unlimited — always selectable."""
    unlimited = _usage(uuid4(), PlanType.recurring, class_count=None, classes_used=999)
    eligible = {unlimited.plan_id}
    assert select_best_membership([unlimited], eligible) is unlimited


# ── stacked packs on the same plan ───────────────────────────────────


def test_select_prefers_oldest_pack_of_same_plan():
    """Two packs on the SAME plan: the older one drains first."""
    plan = uuid4()
    older = _usage(
        plan, PlanType.one_time, class_count=10, classes_used=0,
        item_id=uuid4(), start_date=date(2026, 1, 1),
    )
    newer = _usage(
        plan, PlanType.one_time, class_count=10, classes_used=0,
        item_id=uuid4(), start_date=date(2026, 2, 1),
    )
    chosen = select_best_membership([newer, older], {plan})
    assert chosen is older


def test_depleted_pack_falls_through_to_next_pack():
    """When the oldest same-plan pack is depleted, the next one is chosen."""
    plan = uuid4()
    depleted = _usage(
        plan, PlanType.one_time, class_count=10, classes_used=10,
        item_id=uuid4(), start_date=date(2026, 1, 1),
    )
    fresh = _usage(
        plan, PlanType.one_time, class_count=10, classes_used=0,
        item_id=uuid4(), start_date=date(2026, 2, 1),
    )
    chosen = select_best_membership([depleted, fresh], {plan})
    assert chosen is fresh


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


def test_only_the_depleted_pack_ends():
    """Per-item count: the pack on its last class ends, a sibling does not."""
    plan = uuid4()
    last = _usage(plan, PlanType.one_time, class_count=10, classes_used=9)
    sibling = _usage(plan, PlanType.one_time, class_count=10, classes_used=0)
    assert should_end_membership(last) is True
    assert should_end_membership(sibling) is False


# ── breakdown ────────────────────────────────────────────────────────


def test_breakdown_increments_chosen_membership_usage():
    """The charged membership's usage is +1 and remaining recomputed."""
    chosen = _usage(uuid4(), PlanType.one_time, class_count=5, classes_used=2)
    other = _usage(uuid4(), PlanType.recurring, class_count=None, classes_used=7)
    eligible = {chosen.plan_id}

    breakdown = build_breakdown([chosen, other], eligible, chosen.item_id)
    by_item = {b.item_id: b for b in breakdown}

    assert by_item[chosen.item_id].classes_used == 3
    assert by_item[chosen.item_id].classes_remaining == 2
    assert by_item[chosen.item_id].is_eligible is True
    # The non-chosen membership is unchanged and flagged ineligible.
    assert by_item[other.item_id].classes_used == 7
    assert by_item[other.item_id].is_eligible is False


def test_breakdown_increments_only_charged_pack():
    """Two packs on the same plan: only the charged item shows the +1."""
    plan = uuid4()
    a = _usage(
        plan, PlanType.one_time, class_count=10, classes_used=3,
        item_id=uuid4(), start_date=date(2026, 1, 1),
    )
    b = _usage(
        plan, PlanType.one_time, class_count=10, classes_used=5,
        item_id=uuid4(), start_date=date(2026, 2, 1),
    )
    breakdown = build_breakdown([a, b], {plan}, a.item_id)
    by_item = {x.item_id: x for x in breakdown}

    assert by_item[a.item_id].classes_used == 4
    assert by_item[a.item_id].classes_remaining == 6
    assert by_item[b.item_id].classes_used == 5  # untouched
    assert by_item[b.item_id].classes_remaining == 5


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

    breakdown = build_breakdown([renews, expires], eligible, expires.item_id)
    by_item = {b.item_id: b for b in breakdown}

    assert by_item[renews.item_id].renew_date == date(2026, 7, 1)
    assert by_item[renews.item_id].end_date is None
    assert by_item[expires.item_id].end_date == date(2026, 8, 15)
    assert by_item[expires.item_id].renew_date is None
