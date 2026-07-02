"""Pure selection + breakdown logic for the gated class check-in.

No DB or Stripe — ``CheckinPlanSelector`` decides which active membership covers
a class (trial -> one_time -> recurring, then lowest class_count first, then the
oldest pack within an equal tier so two packs on the same plan drain one fully
before the next), whether a trial / punch-card membership auto-ends once
depleted, and shapes the per-membership usage breakdown returned with the
check-in result. Every method is stateless (a ``@staticmethod``); the class is a
namespace so the logic is grouped rather than a bag of free functions.
"""

from uuid import UUID

from schema.membership_plan import PlanType

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.checkin.schema.checkin_schema import CheckinMembershipBreakdown
from src.checkin.schema.cycle_counts_schema import MembershipUsage

_PLAN_TYPE_PRIORITY: dict[PlanType, int] = {
    PlanType.trial: 0,
    PlanType.one_time: 1,
    PlanType.recurring: 2,
}

_UNLIMITED = float("inf")


class CheckinPlanSelector:
    """Pure membership-selection + breakdown logic for the check-in gate."""

    @staticmethod
    def _sort_memberships_by_priority(
        memberships: list[MembershipUsage],
    ) -> list[MembershipUsage]:
        """Order candidates by selection priority.

        Type (trial < one_time < recurring) — drain the limited trial / one_time
        packs before the unlimited recurring plan, so a pack a member paid for
        actually gets used (an unlimited recurring plan always has capacity and
        would otherwise win every time). Then class_count ascending (unlimited
        last), then the OLDEST pack first (start_date, then item_id) so two packs
        on the same plan drain one fully before the next — matching the
        attendance attribution order.
        """
        return sorted(
            memberships,
            key=lambda m: (
                _PLAN_TYPE_PRIORITY[m.plan_type],
                m.class_count if m.class_count is not None else _UNLIMITED,
                m.start_date,
                m.item_id,
            ),
        )

    @staticmethod
    def select_best_membership(
        memberships: list[MembershipUsage],
        eligible_plan_ids: set[UUID],
    ) -> MembershipUsage | None:
        """Select the best eligible membership with remaining capacity.

        Args:
            memberships: Active memberships with usage.
            eligible_plan_ids: Plans that cover this class.

        Returns:
            The membership row to charge, or None if none qualifies.
        """
        candidates: list[MembershipUsage] = []
        for m in memberships:
            if m.plan_id not in eligible_plan_ids:
                continue
            if m.class_count is not None and m.classes_used >= m.class_count:
                continue
            candidates.append(m)

        if not candidates:
            return None

        return CheckinPlanSelector._sort_memberships_by_priority(candidates)[0]

    @staticmethod
    def select_best_membership_forced(
        memberships: list[MembershipUsage],
    ) -> MembershipUsage | None:
        """Override selection: ignore eligibility AND remaining capacity.

        Used by the coverage / front-desk override path. Picks the highest-
        priority active membership (trial -> one_time -> recurring, then lowest
        class_count, then oldest pack) even when it is ineligible for the class
        or already depleted — over-draw is allowed. Returns None only when the
        member has no active membership to attribute to (a forced check-in still
        needs a non-null plan_id / item_id).
        """
        if not memberships:
            return None
        return CheckinPlanSelector._sort_memberships_by_priority(memberships)[0]

    @staticmethod
    def should_end_membership(membership: MembershipUsage) -> bool:
        """Trial and one_time plans end when their last class is used.

        Recurring and unlimited plans never auto-end. ``classes_used`` is the
        membership's OWN count (per item_id), so a depleted pack ends only
        itself.
        """
        if membership.plan_type == PlanType.recurring:
            return False
        if membership.class_count is None:
            return False
        return membership.classes_used + 1 >= membership.class_count

    @staticmethod
    def build_breakdown(
        memberships: list[MembershipUsage],
        eligible_plan_ids: set[UUID],
        chosen_item_id: UUID | None,
    ) -> list[CheckinMembershipBreakdown]:
        """Build the per-membership breakdown, incrementing the charged
        membership's usage by 1 to reflect the just-inserted check-in.

        Matched on ``item_id``, so with two packs on the same plan only the one
        that was actually charged shows the +1.
        """
        result: list[CheckinMembershipBreakdown] = []
        for m in memberships:
            classes_used = m.classes_used
            if m.item_id == chosen_item_id:
                classes_used += 1

            remaining = None
            if m.class_count is not None:
                remaining = max(0, m.class_count - classes_used)

            result.append(
                CheckinMembershipBreakdown(
                    item_id=m.item_id,
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
