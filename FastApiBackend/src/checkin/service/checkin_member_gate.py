"""Per-member gate + write against a resolved class occurrence.

``checkin_member`` runs the per-member gate + write against a resolved
``OccurrenceContext``, so a batch can resolve once then loop over members.

The gate is faithful to the original CRM: resolve the member's active
memberships, gate by plan eligibility + remaining punch-card capacity + the
room's ``max_capacity``, select the best covering plan (trial -> one_time ->
recurring, then lowest class_count first), log the attendance against that
membership, award the class's points, and auto-end trial / punch-card
memberships once depleted. ``allow_override`` forces past the eligibility,
punch-card, and room gates (front-desk coverage), attributing to the member's
best active membership even if depleted (over-draw allowed); a member with NO
active membership is still skipped. Idempotent: a repeat check-in for the same
(member, class instance) returns the existing row without consuming capacity,
re-awarding points, or re-ending a membership.
"""

from uuid import UUID

from schema.member_membership import MembershipDbStatus

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.checkin.schema.checkin_schema import (
    CheckinMembershipBreakdown,
    CheckinResponse,
    CheckinSkipReason,
    OccurrenceContext,
)
from src.checkin.schema.cycle_counts_schema import (
    ClassesCycleCountsRequest,
    MembershipUsage,
)
from src.checkin.service.checkin_plan_selector import CheckinPlanSelector
from src.checkin.service.checkin_queries import CheckinQueries
from src.checkin.service.checkin_writer import CheckinWriter
from src.checkin.service.cycle_counts_service import CycleCountsService
from src.shared.database import DirectDatabasePool


class CheckinMemberGate:
    """Gates + writes one member against a resolved occurrence.

    Args:
        db_pool: Injected database connection pool.
        cycle_counts_service: Service for fetching cycle usage.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        cycle_counts_service: CycleCountsService,
    ) -> None:
        self._queries = CheckinQueries(db_pool)
        self._writer = CheckinWriter(db_pool)
        self._plan_selector = CheckinPlanSelector()
        self._cycle_counts = cycle_counts_service

    async def checkin_member(
        self,
        ctx: OccurrenceContext,
        member_id: UUID,
        allow_override: bool = False,
    ) -> CheckinResponse:
        """Gate + write one member against a resolved occurrence.

        Args:
            ctx: The resolved occurrence (from the occurrence resolver).
            member_id: The member checking in.
            allow_override: When True, bypass the eligibility, punch-card, and
                room-capacity gates (coverage); attribute to the member's best
                active membership even if depleted. A member with no active
                membership is still skipped.

        Returns:
            The check-in result (recorded, idempotent repeat, or skipped).
        """
        existing = await self._queries.get_existing_attendance(
            member_id, ctx.class_history_id
        )
        if existing is not None:
            return self._already_checked_in(
                ctx,
                member_id,
                existing["log_id"],
                existing["plan_id"],
                existing["item_id"],
            )

        if not allow_override and ctx.max_capacity is not None:
            count = await self._queries.count_attendance(ctx.class_history_id)
            if count >= ctx.max_capacity:
                return self._skipped(
                    ctx, member_id, CheckinSkipReason.capacity_full, []
                )

        active = await self._active_memberships(member_id, ctx.gym_id)
        if not active:
            return self._skipped(
                ctx, member_id, CheckinSkipReason.no_membership, []
            )

        eligible = await self._queries.get_eligible_plans(
            ctx.gym_id,
            ctx.class_id,
            [m.plan_id for m in active],
        )
        chosen = (
            self._plan_selector.select_best_membership_forced(active)
            if allow_override
            else self._plan_selector.select_best_membership(active, eligible)
        )
        if chosen is None:
            breakdown = self._plan_selector.build_breakdown(
                active, eligible, None
            )
            return self._skipped(
                ctx, member_id, CheckinSkipReason.no_eligible_plan, breakdown
            )

        should_end = self._plan_selector.should_end_membership(chosen)

        log_id, already, points = await self._writer.write_checkin(
            ctx,
            member_id,
            chosen.plan_id,
            chosen.item_id,
            should_end,
        )

        if already:
            return self._already_checked_in(
                ctx, member_id, log_id, chosen.plan_id, chosen.item_id
            )

        return CheckinResponse(
            log_id=log_id,
            member_id=member_id,
            class_history_id=ctx.class_history_id,
            class_id=ctx.class_id,
            already_checked_in=False,
            chosen_plan_id=chosen.plan_id,
            chosen_item_id=chosen.item_id,
            points_awarded=points,
            skip_reason=None,
            memberships=self._plan_selector.build_breakdown(
                active, eligible, chosen.item_id
            ),
        )

    # -- helpers ---------------------------------------------------------

    async def _active_memberships(
        self,
        member_id: UUID,
        gym_id: UUID,
    ) -> list[MembershipUsage]:
        """Return the member's active memberships with current usage."""
        counts_request = ClassesCycleCountsRequest(
            gym_id=gym_id,
            member_ids=[member_id],
        )
        counts = await self._cycle_counts.get_cycle_counts(counts_request)
        if not counts.users:
            return []
        return [
            m
            for m in counts.users[0].memberships
            if m.status == MembershipDbStatus.active
        ]

    def _already_checked_in(
        self,
        ctx: OccurrenceContext,
        member_id: UUID,
        log_id: UUID,
        plan_id: UUID,
        item_id: UUID,
    ) -> CheckinResponse:
        """Build the idempotent-repeat response (no points re-awarded)."""
        return CheckinResponse(
            log_id=log_id,
            member_id=member_id,
            class_history_id=ctx.class_history_id,
            class_id=ctx.class_id,
            already_checked_in=True,
            chosen_plan_id=plan_id,
            chosen_item_id=item_id,
            points_awarded=0,
            skip_reason=None,
            memberships=[],
        )

    def _skipped(
        self,
        ctx: OccurrenceContext,
        member_id: UUID,
        reason: CheckinSkipReason,
        memberships: list[CheckinMembershipBreakdown],
    ) -> CheckinResponse:
        """Build a skip response (nothing written, no points awarded)."""
        return CheckinResponse(
            log_id=None,
            member_id=member_id,
            class_history_id=ctx.class_history_id,
            class_id=ctx.class_id,
            already_checked_in=False,
            chosen_plan_id=None,
            chosen_item_id=None,
            points_awarded=0,
            skip_reason=reason,
            memberships=memberships,
        )
