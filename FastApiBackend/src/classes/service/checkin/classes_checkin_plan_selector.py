"""Pure selection + breakdown logic for the gated class check-in.

No DB or Stripe — these functions decide which active membership covers a
class (trial -> one_time -> recurring, then lowest class_count first),
whether a trial / punch-card plan auto-ends once depleted, and shape the
per-membership usage breakdown returned with the check-in result.
"""

from uuid import UUID

from schema.membership_plan import PlanType

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.classes.schema.classes_cycle_counts_schema import MembershipUsage
from src.classes.schema.classes_plan_type import PlanInfo
from src.classes.schema.classes_schema import CheckinMembershipBreakdown

_PLAN_TYPE_PRIORITY: dict[PlanType, int] = {
    PlanType.trial: 0,
    PlanType.recurring: 1,
    PlanType.one_time: 2,
}

_UNLIMITED = float("inf")


def _sort_plans_by_priority(plans: list[PlanInfo]) -> list[PlanInfo]:
    """Sort by type priority (trial < one_time < recurring), then by
    class_count ascending (unlimited last)."""
    return sorted(
        plans,
        key=lambda p: (
            _PLAN_TYPE_PRIORITY[p.plan_type],
            p.class_count if p.class_count is not None else _UNLIMITED,
        ),
    )


def select_best_plan(
    memberships: list[MembershipUsage],
    eligible_plan_ids: set[UUID],
) -> UUID | None:
    """Select the best eligible plan with remaining capacity.

    Args:
        memberships: Active memberships with usage.
        eligible_plan_ids: Plans that cover this class.

    Returns:
        The plan_id to charge, or None if none qualifies.
    """
    candidates: list[PlanInfo] = []
    for m in memberships:
        if m.plan_id not in eligible_plan_ids:
            continue
        if m.class_count is not None and m.classes_used >= m.class_count:
            continue
        candidates.append(
            PlanInfo(
                plan_id=m.plan_id,
                plan_type=m.plan_type,
                class_count=m.class_count,
            )
        )

    if not candidates:
        return None

    return _sort_plans_by_priority(candidates)[0].plan_id


def should_end_membership(membership: MembershipUsage) -> bool:
    """Trial and one_time plans end when their last class is used.

    Recurring and unlimited plans never auto-end.
    """
    if membership.plan_type == PlanType.recurring:
        return False
    if membership.class_count is None:
        return False
    return membership.classes_used + 1 >= membership.class_count


def build_breakdown(
    memberships: list[MembershipUsage],
    eligible_plan_ids: set[UUID],
    chosen_plan_id: UUID | None,
) -> list[CheckinMembershipBreakdown]:
    """Build the per-membership breakdown, incrementing the charged
    plan's usage by 1 to reflect the just-inserted check-in."""
    result: list[CheckinMembershipBreakdown] = []
    for m in memberships:
        classes_used = m.classes_used
        if m.plan_id == chosen_plan_id:
            classes_used += 1

        remaining = None
        if m.class_count is not None:
            remaining = max(0, m.class_count - classes_used)

        result.append(
            CheckinMembershipBreakdown(
                plan_id=m.plan_id,
                plan_type=m.plan_type,
                class_count=m.class_count,
                classes_used=classes_used,
                classes_remaining=remaining,
                is_eligible=m.plan_id in eligible_plan_ids,
                renew_date=m.renew_date,
                end_date=m.end_date,
            )
        )
    return result
