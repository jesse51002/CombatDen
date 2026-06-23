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

from schema.membership_plan import PlanType

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.classes.schema.classes_cycle_counts_schema import MembershipUsage
from src.members.schema.members_crm_members_list_schema import (
    CrmMemberStatus,
)
from src.members.service.member_details.members_billing_grouper import (
    MembersBillingGrouper,
    MembershipOverviewContext,
    OverviewKind,
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
        # Defaults to self-pay (payer == member); override for linked payers.
        "paid_by_member_id": member_id,
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


def test_plan_total_sums_only_active_member_shares():
    """Plan-level total_price = sum of the ACTIVE memberships' own shares;
    frozen (paused) and cancelled (stale total_price) rows are excluded, and
    each member keeps its own per-membership share in ``members``."""
    grouper = MembersBillingGrouper()
    plan_id = uuid4()
    parent = _membership_row(
        status="active", next_due=FUTURE, plan_id=plan_id, total_price=5000
    )
    child = _membership_row(
        status="active", next_due=FUTURE, plan_id=plan_id, total_price=3000
    )
    frozen = _membership_row(
        status="frozen", next_due=FUTURE, plan_id=plan_id, total_price=7777
    )
    cancelled = _membership_row(
        status="cancelled", next_due=None, plan_id=plan_id, total_price=9999
    )

    grouped = grouper.group_by_plan(
        [parent, child, frozen, cancelled],
        _StubSupplementary(),
        {},
        parent["member_id"],
        TODAY,
    )

    assert len(grouped) == 1
    # 5000 + 3000 (active) only; frozen 7777 and cancelled 9999 excluded.
    assert grouped[0].total_price == 8000
    assert grouped[0].members[parent["member_id"]].total_price == 5000
    assert grouped[0].members[child["member_id"]].total_price == 3000


def _pack_usage(row: dict, used: int) -> MembershipUsage:
    return MembershipUsage(
        item_id=row["item_id"],
        plan_id=row["plan_id"],
        start_date=row["membership_start_date"],
        plan_type=PlanType.one_time,
        status="active",
        class_count=10,
        classes_used=used,
        classes_remaining=10 - used,
        renew_date=None,
        end_date=None,
    )


def test_one_time_packs_split_into_per_item_cards():
    """Two one_time packs on the SAME plan for one member become TWO cards,
    each carrying its OWN class usage (looked up by item_id, not collapsed)."""
    grouper = MembersBillingGrouper()
    member_id = uuid4()
    plan_id = uuid4()
    pack_a = _membership_row(
        status="active", next_due=None, plan_id=plan_id,
        plan_type="one_time", member_id=member_id,
        paid_by_member_id=member_id,
    )
    pack_b = _membership_row(
        status="active", next_due=None, plan_id=plan_id,
        plan_type="one_time", member_id=member_id,
        paid_by_member_id=member_id,
    )
    usage_lookup = {
        (member_id, pack_a["item_id"]): _pack_usage(pack_a, used=4),
        (member_id, pack_b["item_id"]): _pack_usage(pack_b, used=1),
    }

    grouped = grouper.group_by_plan(
        [pack_a, pack_b],
        _StubSupplementary(),
        usage_lookup,
        member_id,
        TODAY,
    )

    # Two separate cards (one per pack), NOT collapsed into one.
    assert len(grouped) == 2
    by_item = {g.members[member_id].item_id: g for g in grouped}
    assert by_item[pack_a["item_id"]].paying_for[0].classes_used == 4
    assert by_item[pack_b["item_id"]].paying_for[0].classes_used == 1


def test_recurring_family_stays_one_card():
    """A recurring plan shared by two members stays ONE card with both in
    paying_for (only one_time / trial packs split per item)."""
    grouper = MembersBillingGrouper()
    plan_id = uuid4()
    parent = _membership_row(status="active", next_due=FUTURE, plan_id=plan_id)
    child = _membership_row(status="active", next_due=FUTURE, plan_id=plan_id)

    grouped = grouper.group_by_plan(
        [parent, child],
        _StubSupplementary(),
        {},
        parent["member_id"],
        TODAY,
    )

    assert len(grouped) == 1
    assert len(grouped[0].paying_for) == 2


class _PayerSupp:
    """Stub supplementary exposing a single payer profile by id."""

    def __init__(self, payer_id, first_name: str) -> None:
        class _Profile:
            pass

        profile = _Profile()
        profile.first_name = first_name
        self.profiles_dict = {payer_id: profile}


def _overview_ctx(**overrides) -> MembershipOverviewContext:
    """Build a MembershipOverviewContext with self-pay defaults.

    ``own_payer_ids`` defaults to the viewer paying themselves; override it
    (and ``kind``) for the beneficiary / payer-for-others cases.
    """
    member_id = overrides.pop("viewed_member_id", uuid4())
    defaults = {
        "kind": OverviewKind.self_pay,
        "total": 12000,
        "has_trial": False,
        "has_cancelled": False,
        "has_frozen": False,
        "has_overdue": False,
        "paying_count": 1,
        "members_paid_for_count": 0,
        "own_payer_ids": frozenset({member_id}),
        "viewed_member_id": member_id,
    }
    defaults.update(overrides)
    return MembershipOverviewContext(**defaults)


def test_overview_self_pay_singular():
    grouper = MembersBillingGrouper()
    ctx = _overview_ctx(total=13784, paying_count=1)
    assert (
        grouper.build_membership_overview(ctx, None)
        == "Paying $137.84/mo for 1 Membership"
    )


def test_overview_self_pay_plural():
    grouper = MembersBillingGrouper()
    ctx = _overview_ctx(total=20000, paying_count=2)
    assert (
        grouper.build_membership_overview(ctx, None)
        == "Paying $200/mo for 2 Memberships"
    )


def test_overview_reflects_overdue_with_price():
    grouper = MembersBillingGrouper()
    ctx = _overview_ctx(total=12000, has_overdue=True, paying_count=1)
    assert (
        grouper.build_membership_overview(ctx, None)
        == "Overdue · $120/mo for 1 Membership"
    )


def test_overview_reflects_overdue_without_price():
    grouper = MembersBillingGrouper()
    ctx = _overview_ctx(total=0, has_overdue=True, paying_count=1)
    assert grouper.build_membership_overview(ctx, None) == "Overdue for 1 Membership"


def test_overview_pays_for_others_counts_self_plus_others():
    """A payer-for-others reads 'across N members' — N counts the payer too
    when they hold a membership in the set (parent + 2 kids = 3)."""
    grouper = MembersBillingGrouper()
    ctx = _overview_ctx(
        kind=OverviewKind.pays_for_others,
        total=41250,
        members_paid_for_count=3,
        paying_count=3,
    )
    assert (
        grouper.build_membership_overview(ctx, None)
        == "Paying $412.50/mo across 3 members"
    )


def test_overview_beneficiary_all_paid_by_parent():
    """A child whose memberships are all paid by the parent reads
    '$X/mo worth of memberships (Paid by <parent>)' — no 'self'."""
    grouper = MembersBillingGrouper()
    child_id, parent_id = uuid4(), uuid4()
    ctx = _overview_ctx(
        kind=OverviewKind.beneficiary,
        total=13784,
        viewed_member_id=child_id,
        own_payer_ids=frozenset({parent_id}),
    )
    assert (
        grouper.build_membership_overview(ctx, _PayerSupp(parent_id, "Cynthia"))
        == "$137.84/mo worth of memberships (Paid by Cynthia)"
    )


def test_overview_beneficiary_split_self_and_parent():
    """A split beneficiary lists self first, then the parent."""
    grouper = MembersBillingGrouper()
    child_id, parent_id = uuid4(), uuid4()
    ctx = _overview_ctx(
        kind=OverviewKind.beneficiary,
        total=20000,
        viewed_member_id=child_id,
        own_payer_ids=frozenset({child_id, parent_id}),
    )
    assert (
        grouper.build_membership_overview(ctx, _PayerSupp(parent_id, "Cynthia"))
        == "$200/mo worth of memberships (Paid by self / Cynthia)"
    )


def test_overview_frozen_wins_over_overdue():
    # A frozen account pauses billing, so frozen takes precedence.
    grouper = MembersBillingGrouper()
    ctx = _overview_ctx(
        total=12000, has_frozen=True, has_overdue=True, paying_count=0
    )
    assert grouper.build_membership_overview(ctx, None) == "Account is Frozen"


def test_overview_beneficiary_frozen_keeps_payer_suffix():
    """A frozen beneficiary still shows who pays — the suffix survives the
    salient-state short-circuit."""
    grouper = MembersBillingGrouper()
    child_id, parent_id = uuid4(), uuid4()
    ctx = _overview_ctx(
        kind=OverviewKind.beneficiary,
        total=0,
        has_frozen=True,
        paying_count=0,
        viewed_member_id=child_id,
        own_payer_ids=frozenset({parent_id}),
    )
    assert (
        grouper.build_membership_overview(ctx, _PayerSupp(parent_id, "Cynthia"))
        == "Account is Frozen (Paid by Cynthia)"
    )
