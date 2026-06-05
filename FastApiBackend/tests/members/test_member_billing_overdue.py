"""Regression: the CRM member-detail read path derives 'overdue'.

A member whose membership ``next_due_date`` has passed must surface as
``overdue`` on the detail screen — both the per-membership status badge
and the profile-header overview line.

The bug this guards: the detail path passed the raw DB status
(``active`` / ``frozen`` / ``cancelled`` / ``ended``) straight through and
never compared ``next_due_date`` to the gym's local date, so an overdue
member always read as ``active`` ("Active for 1 Membership"). The
members-list endpoint already derived overdue; these tests lock in that
the detail endpoint agrees, via the shared ``is_membership_overdue`` rule.

Pure unit tests over the grouper + helper — no DB/Stripe. The service
wiring (``gym_today`` from ``member_details.sql`` threaded into the
grouper) is covered by the billing-detail integration tests.
"""

from datetime import date
from uuid import uuid4

from src.members.schema.members_crm_members_list_schema import (
    CrmMemberStatus,
)
from src.members.service.member_details.members_billing_grouper import (
    MembersBillingGrouper,
)
from src.members.service.members_status_mapping import is_membership_overdue

TODAY = date(2026, 6, 4)
PAST = date(2026, 5, 1)
FUTURE = date(2026, 7, 1)


class _StubSupplementary:
    """Minimal stand-in: the grouper only reads ``profiles_dict`` here."""

    profiles_dict: dict = {}


def _membership_row(*, status: str, next_due: date | None, **overrides) -> dict:
    """Build one member_details.sql-shaped row for the grouper."""
    row = {
        "plan_id": uuid4(),
        "plan_name": "Unlimited",
        "plan_type": "recurring",
        "membership_status": status,
        "next_due_date": next_due,
        "base_cost": 12000,
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
        "member_id": uuid4(),
        "item_id": uuid4(),
        "first_name": "Ada",
        "last_name": "Lovelace",
        "photo_url": None,
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


def test_group_by_plan_marks_past_due_membership_overdue():
    grouper = MembersBillingGrouper()
    row = _membership_row(status="active", next_due=PAST)

    grouped = grouper.group_by_plan(
        [row],
        _StubSupplementary(),
        {},
        row["member_id"],
        TODAY,
    )

    assert len(grouped) == 1
    # The carousel status badge.
    assert grouped[0].status == CrmMemberStatus.overdue
    # The covered member in the paying-for list reads overdue too.
    assert grouped[0].paying_for[0].status == CrmMemberStatus.overdue


def test_group_by_plan_keeps_active_when_not_past_due():
    grouper = MembersBillingGrouper()
    row = _membership_row(status="active", next_due=FUTURE)

    grouped = grouper.group_by_plan(
        [row],
        _StubSupplementary(),
        {},
        row["member_id"],
        TODAY,
    )

    assert grouped[0].status == CrmMemberStatus.active
    assert grouped[0].paying_for[0].status == CrmMemberStatus.active


def test_overview_reflects_overdue_with_price():
    grouper = MembersBillingGrouper()

    overview, linked = grouper.build_membership_overview(
        linked_to_id=None,
        monthly_total=12000,
        has_trial=False,
        has_cancelled=False,
        has_frozen=False,
        has_overdue=True,
        paying_count=1,
        supplementary=None,
    )

    assert linked is None
    assert overview == "Overdue · $120/mo for 1 Membership"


def test_overview_reflects_overdue_without_price():
    grouper = MembersBillingGrouper()

    overview, _ = grouper.build_membership_overview(
        linked_to_id=None,
        monthly_total=0,
        has_trial=False,
        has_cancelled=False,
        has_frozen=False,
        has_overdue=True,
        paying_count=1,
        supplementary=None,
    )

    assert overview == "Overdue for 1 Membership"


def test_price_summary_frozen_wins_over_overdue():
    # A frozen account pauses billing, so frozen takes precedence.
    grouper = MembersBillingGrouper()

    summary = grouper._build_price_summary(
        12000,
        False,  # has_trial
        False,  # has_cancelled
        True,  # has_frozen
        True,  # has_overdue
        0,  # paying_count
    )

    assert summary == "Account is Frozen"
