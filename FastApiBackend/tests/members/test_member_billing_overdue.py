"""Regression + unit coverage for the member-detail carousel + overview.

A member whose membership ``next_due_date`` has passed must surface as
``overdue`` on the detail screen — both the per-membership status badge
and the profile-header overview line.

The bug this guards: the detail path passed the raw DB status
(``active`` / ``frozen`` / ``cancelled`` / ``ended``) straight through and
never compared ``next_due_date`` to the gym's local date, so an overdue
member always read as ``active`` ("Active for 1 Membership"). The
members-list endpoint already derived overdue; these tests lock in that
the detail endpoint agrees, via the shared ``is_membership_overdue`` rule.

Also covers the single-member card shape: the carousel is scoped to the
viewed member and ``member_details.sql`` returns one row per (member, plan),
so each row becomes exactly one card with its own membership fields inlined.

Pure unit tests over the grouper + helper — no DB/Stripe. The service
wiring (``gym_today`` from ``member_details.sql`` threaded into the
grouper) is covered by the billing-detail integration tests.
"""

from datetime import date
from uuid import uuid4

from schema.membership_plan import PlanType

from src.classes.schema.classes_cycle_counts_schema import MembershipUsage
from src.members.schema.members_crm_members_list_schema import (
    CrmMemberStatus,
)
from src.members.service.member_details.members_billing_grouper import (
    MembersBillingGrouper,
    MembershipOverviewContext,
)
from src.members.service.members_status_mapping import is_membership_overdue

TODAY = date(2026, 6, 4)
PAST = date(2026, 5, 1)
FUTURE = date(2026, 7, 1)


def _membership_row(*, status: str, next_due: date | None, **overrides) -> dict:
    """Build one member_details.sql-shaped row for the grouper."""
    member_id = uuid4()
    row = {
        "plan_id": uuid4(),
        "plan_name": "Unlimited",
        "plan_type": "recurring",
        "membership_status": status,
        "next_due_date": next_due,
        "base_cost": 12000,
        "current_active_price": 12000,
        "duration_amount": 1,
        "duration_unit": "month",
        "total_price": 12000,
        "last_paid_date": PAST,
        "membership_start_date": date(2026, 1, 1),
        "membership_end_date": None,
        "membership_cancel_date": None,
        "freeze_start_date": None,
        "freeze_end_date": None,
        "on_outdated_price": False,
        "member_id": member_id,
        "paid_by_member_id": member_id,
        "item_id": uuid4(),
        "applied_discounts": [],
    }
    row.update(overrides)
    return row


def test_is_membership_overdue_truth_table():
    assert is_membership_overdue("active", PAST, TODAY) is True
    assert is_membership_overdue("active", FUTURE, TODAY) is False
    assert is_membership_overdue("active", None, TODAY) is False
    # Cancelled is never overdue, even when past due.
    assert is_membership_overdue("cancelled", PAST, TODAY) is False
    # Strictly past — the due date itself is not yet overdue.
    assert is_membership_overdue("active", TODAY, TODAY) is False


def test_card_marks_past_due_membership_overdue():
    grouper = MembersBillingGrouper()
    row = _membership_row(status="active", next_due=PAST)

    cards = grouper.build_membership_cards([row], {}, TODAY)

    assert len(cards) == 1
    assert cards[0].status == CrmMemberStatus.overdue


def test_card_keeps_active_when_not_past_due():
    grouper = MembersBillingGrouper()
    row = _membership_row(status="active", next_due=FUTURE)

    cards = grouper.build_membership_cards([row], {}, TODAY)

    assert cards[0].status == CrmMemberStatus.active


def test_card_inlines_membership_fields():
    """Each card carries its own membership's fields directly (no nested
    members map): item_id, paid_by_member_id, and its own price."""
    grouper = MembersBillingGrouper()
    row = _membership_row(status="active", next_due=FUTURE, total_price=5000)

    cards = grouper.build_membership_cards([row], {}, TODAY)

    card = cards[0]
    assert card.item_id == row["item_id"]
    assert card.paid_by_member_id == row["paid_by_member_id"]
    assert card.total_price == 5000


def test_card_keeps_own_price_when_frozen():
    """A frozen card shows its own total_price — the status badge conveys
    frozen; we do NOT zero it out."""
    grouper = MembersBillingGrouper()
    row = _membership_row(status="frozen", next_due=FUTURE, total_price=7777)

    cards = grouper.build_membership_cards([row], {}, TODAY)

    assert cards[0].status == CrmMemberStatus.frozen
    assert cards[0].total_price == 7777


def test_one_card_per_row():
    """Distinct rows yield distinct cards — no cross-row grouping."""
    grouper = MembersBillingGrouper()
    a = _membership_row(status="active", next_due=FUTURE)
    b = _membership_row(status="active", next_due=FUTURE)

    cards = grouper.build_membership_cards([a, b], {}, TODAY)

    assert len(cards) == 2


def _usage(plan_id, **overrides) -> MembershipUsage:
    defaults = {
        "plan_id": plan_id,
        "plan_type": PlanType.recurring,
        "status": "active",
        "class_count": 12,
        "classes_used": 3,
        "classes_remaining": 9,
        "renew_date": FUTURE,
        "end_date": None,
    }
    defaults.update(overrides)
    return MembershipUsage(**defaults)


def test_card_inlines_cycle_usage():
    grouper = MembersBillingGrouper()
    row = _membership_row(status="active", next_due=FUTURE)
    lookup = {(row["member_id"], row["plan_id"]): _usage(row["plan_id"])}

    cards = grouper.build_membership_cards([row], lookup, TODAY)

    assert cards[0].class_count == 12
    assert cards[0].classes_used == 3
    assert cards[0].classes_remaining == 9


def test_card_usage_defaults_when_absent():
    grouper = MembersBillingGrouper()
    row = _membership_row(status="active", next_due=FUTURE)

    cards = grouper.build_membership_cards([row], {}, TODAY)

    assert cards[0].class_count is None
    assert cards[0].classes_used == 0
    assert cards[0].classes_remaining is None


def _overview_ctx(**overrides) -> MembershipOverviewContext:
    """Build a MembershipOverviewContext with self-pay defaults."""
    defaults = {
        "total": 12000,
        "has_trial": False,
        "has_cancelled": False,
        "has_frozen": False,
        "has_overdue": False,
        "paying_count": 1,
    }
    defaults.update(overrides)
    return MembershipOverviewContext(**defaults)


def test_overview_singular():
    grouper = MembersBillingGrouper()
    ctx = _overview_ctx(total=13784, paying_count=1)
    assert (
        grouper.build_membership_overview(ctx)
        == "Paying $137.84/mo for 1 Membership"
    )


def test_overview_plural():
    grouper = MembersBillingGrouper()
    ctx = _overview_ctx(total=20000, paying_count=2)
    assert (
        grouper.build_membership_overview(ctx)
        == "Paying $200/mo for 2 Memberships"
    )


def test_overview_reflects_overdue_with_price():
    grouper = MembersBillingGrouper()
    ctx = _overview_ctx(total=12000, has_overdue=True, paying_count=1)
    assert (
        grouper.build_membership_overview(ctx)
        == "Overdue · $120/mo for 1 Membership"
    )


def test_overview_reflects_overdue_without_price():
    grouper = MembersBillingGrouper()
    ctx = _overview_ctx(total=0, has_overdue=True, paying_count=1)
    assert grouper.build_membership_overview(ctx) == "Overdue for 1 Membership"


def test_overview_frozen_wins_over_overdue():
    # A frozen account pauses billing, so frozen takes precedence.
    grouper = MembersBillingGrouper()
    ctx = _overview_ctx(
        total=12000, has_frozen=True, has_overdue=True, paying_count=0
    )
    assert grouper.build_membership_overview(ctx) == "Account is Frozen"
