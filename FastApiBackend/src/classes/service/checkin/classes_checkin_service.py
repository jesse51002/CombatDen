"""Service for checking a member into a class with automatic plan selection.

The check-in is gated, faithful to the original CRM: it resolves the member's
active memberships, computes per-cycle usage, gates by plan eligibility and
remaining capacity, selects the best covering plan (trial -> one_time ->
recurring, then lowest class_count first), logs the attendance against that
membership, and auto-ends trial / punch-card memberships once depleted. If no
plan covers the class with capacity, the check-in is rejected and nothing is
written. Idempotent: a repeat check-in for the same (member, class instance)
returns the existing row without consuming capacity or re-ending a membership.

The orchestrator composes three pieces: ``ClassesCheckinQueries`` (DB reads),
``ClassesCheckinWriter`` (the transactional write + auto-end), and the pure
``classes_checkin_plan_selector`` functions (selection + breakdown logic).
"""

from uuid import UUID

from schema.member_membership import MembershipDbStatus

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.classes.schema.classes_cycle_counts_schema import (
    ClassesCycleCountsRequest,
    MembershipUsage,
)
from src.classes.schema.classes_schema import (
    CheckinMembershipBreakdown,
    CheckinRequest,
    CheckinResponse,
)
from src.classes.service.checkin.classes_checkin_plan_selector import (
    build_breakdown,
    select_best_plan,
    should_end_membership,
)
from src.classes.service.checkin.classes_checkin_queries import (
    ClassesCheckinQueries,
)
from src.classes.service.checkin.classes_checkin_writer import (
    ClassesCheckinWriter,
)
from src.classes.service.classes_cycle_counts_service import (
    ClassesCycleCountsService,
)
from src.shared.database import DirectDatabasePool


class ClassesCheckinService:
    """Checks a member into a class, selecting the best membership plan.

    Args:
        db_pool: Injected database connection pool.
        cycle_counts_service: Service for fetching cycle usage.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        cycle_counts_service: ClassesCycleCountsService,
    ) -> None:
        self._queries = ClassesCheckinQueries(db_pool)
        self._writer = ClassesCheckinWriter(db_pool)
        self._cycle_counts = cycle_counts_service

    async def checkin(self, request: CheckinRequest) -> CheckinResponse:
        """Check a member into a class instance.

        Args:
            request: Member, gym, and class_history identifiers.

        Returns:
            Check-in result with chosen plan/membership and the usage
            breakdown, or a rejection (null log_id) when no plan covers
            the class with remaining capacity.

        Raises:
            ValueError: If the class_history instance does not exist.
        """
        class_id = await self._queries.resolve_class_id(request)
        if class_id is None:
            raise ValueError(f"class_history_id {request.class_history_id} not found")

        existing = await self._queries.get_existing_attendance(request)
        if existing is not None:
            return self._already_checked_in(
                request,
                existing["log_id"],
                existing["plan_id"],
                existing["item_id"],
            )

        active = await self._active_memberships(request)
        if not active:
            return self._rejected(request, [])

        eligible = await self._queries.get_eligible_plans(
            request.gym_id,
            class_id,
            [m.plan_id for m in active],
        )
        chosen_plan_id = select_best_plan(active, eligible)
        if chosen_plan_id is None:
            breakdown = build_breakdown(active, eligible, None)
            return self._rejected(request, breakdown)

        item_id = await self._queries.resolve_item_id(request, chosen_plan_id)
        if item_id is None:
            breakdown = build_breakdown(active, eligible, None)
            return self._rejected(request, breakdown)

        chosen = next(m for m in active if m.plan_id == chosen_plan_id)
        should_end = should_end_membership(chosen)

        log_id, already = await self._writer.write_checkin(
            request,
            chosen_plan_id,
            item_id,
            should_end,
        )

        if already:
            return self._already_checked_in(
                request,
                log_id,
                chosen_plan_id,
                item_id,
            )

        return CheckinResponse(
            log_id=log_id,
            member_id=request.member_id,
            class_history_id=request.class_history_id,
            already_checked_in=False,
            chosen_plan_id=chosen_plan_id,
            chosen_item_id=item_id,
            memberships=build_breakdown(active, eligible, chosen_plan_id),
        )

    async def _active_memberships(
        self,
        request: CheckinRequest,
    ) -> list[MembershipUsage]:
        """Return the member's active memberships with current usage."""
        counts_request = ClassesCycleCountsRequest(
            gym_id=request.gym_id,
            member_ids=[request.member_id],
        )
        counts = await self._cycle_counts.get_cycle_counts(counts_request)
        if not counts.users:
            return []
        return [m for m in counts.users[0].memberships if m.status == MembershipDbStatus.active]

    def _already_checked_in(
        self,
        request: CheckinRequest,
        log_id: UUID,
        plan_id: UUID,
        item_id: UUID,
    ) -> CheckinResponse:
        """Build the idempotent-repeat response."""
        return CheckinResponse(
            log_id=log_id,
            member_id=request.member_id,
            class_history_id=request.class_history_id,
            already_checked_in=True,
            chosen_plan_id=plan_id,
            chosen_item_id=item_id,
            memberships=[],
        )

    def _rejected(
        self,
        request: CheckinRequest,
        memberships: list[CheckinMembershipBreakdown],
    ) -> CheckinResponse:
        """Build a hard-gate rejection response (nothing written)."""
        return CheckinResponse(
            log_id=None,
            member_id=request.member_id,
            class_history_id=request.class_history_id,
            already_checked_in=False,
            chosen_plan_id=None,
            chosen_item_id=None,
            memberships=memberships,
        )
