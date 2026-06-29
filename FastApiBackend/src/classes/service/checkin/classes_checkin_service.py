"""Service for checking a member into a class with automatic plan selection.

The check-in is split into two reusable seams:

* ``resolve_occurrence`` turns ``(class_id, gym_id, occurrence_date)`` into an
  ``OccurrenceContext``: it loads the class, validates that the date is a real,
  non-cancelled occurrence by running the canonical ``ClassesExpander`` over
  that single day (so exception-applied time / instructor / duration and the
  gym-tz UTC ``occurred_at`` are exact), then lazily find-or-creates the
  ``class_history`` row via ``ClassesMaterializer`` (idempotent + race-safe).
* ``checkin_member`` runs the per-member gate + write against a resolved
  occurrence, so a future batch can resolve once then loop over members.

The per-member gate is faithful to the original CRM: resolve the member's
active memberships, gate by plan eligibility + remaining punch-card capacity +
the room's ``max_capacity``, select the best covering plan (trial -> one_time
-> recurring, then lowest class_count first), log the attendance against that
membership, award the class's points, and auto-end trial / punch-card
memberships once depleted. ``allow_override`` forces past the eligibility,
punch-card, and room gates (front-desk coverage), attributing to the member's
best active membership even if depleted (over-draw allowed); a member with NO
active membership is still skipped. Idempotent: a repeat check-in for the same
(member, class instance) returns the existing row without consuming capacity,
re-awarding points, or re-ending a membership.
"""

import json
from datetime import date
from uuid import UUID

from schema.member_membership import MembershipDbStatus

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.classes.schema.classes_cycle_counts_schema import (
    ClassesCycleCountsRequest,
    MembershipUsage,
)
from src.classes.schema.classes_expander_schema import EffectiveOccurrence
from src.classes.schema.classes_schema import (
    CheckinMembershipBreakdown,
    CheckinRequest,
    CheckinResponse,
    CheckinSkipReason,
    OccurrenceContext,
)
from src.classes.service.checkin.classes_checkin_plan_selector import (
    build_breakdown,
    select_best_membership,
    select_best_membership_forced,
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
from src.classes.service.classes_expander import ClassesExpander
from src.classes.service.classes_expander_mapping import (
    to_expander_class,
    to_expander_instance,
    to_expander_range,
)
from src.classes.service.classes_materializer import ClassesMaterializer
from src.shared.database import DirectDatabasePool


class ClassesCheckinService:
    """Checks a member into a class, selecting the best membership plan.

    Args:
        db_pool: Injected database connection pool.
        cycle_counts_service: Service for fetching cycle usage.
        expander: The canonical recurrence + exception expander (pure).
        materializer: Lazy find-or-create of the class_history occurrence.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        cycle_counts_service: ClassesCycleCountsService,
        expander: ClassesExpander,
        materializer: ClassesMaterializer,
    ) -> None:
        self._queries = ClassesCheckinQueries(db_pool)
        self._writer = ClassesCheckinWriter(db_pool)
        self._cycle_counts = cycle_counts_service
        self._expander = expander
        self._materializer = materializer

    async def checkin(self, request: CheckinRequest) -> CheckinResponse:
        """Resolve the occurrence, then check the member in.

        Args:
            request: member / gym / class identifiers, the occurrence date, and
                the override flag.

        Returns:
            The check-in result (recorded, idempotent repeat, or skipped).

        Raises:
            ValueError: If the class is missing / deleted / inactive, or the
                date is not a real, non-cancelled occurrence (mapped to
                404 / 400 by the router).
        """
        ctx = await self.resolve_occurrence(
            request.class_id, request.gym_id, request.occurrence_date
        )
        return await self.checkin_member(
            ctx, request.member_id, request.allow_override
        )

    async def resolve_occurrence(
        self,
        class_id: UUID,
        gym_id: UUID,
        occurrence_date: date,
    ) -> OccurrenceContext:
        """Resolve + materialize a single class occurrence.

        Raises:
            ValueError: If the class does not exist / is deleted / is inactive,
                the gym is missing, or no real non-cancelled occurrence lands on
                ``occurrence_date``.
        """
        class_row = await self._queries.get_class_for_checkin(
            class_id, gym_id, occurrence_date
        )
        if class_row is None:
            raise ValueError("Class not found")
        if class_row["is_deleted"]:
            raise ValueError("Class has been deleted")
        if not class_row["is_active"]:
            raise ValueError("Class is not active")

        gym_tz = await self._queries.get_gym_timezone(gym_id)
        if gym_tz is None:
            raise ValueError("Gym not found")

        occurrence = await self._expand_single_day(
            class_row, class_id, occurrence_date, gym_tz
        )
        if occurrence is None:
            raise ValueError(
                f"No class occurrence on {occurrence_date} for this class"
            )

        effective_capacity = (
            class_row["exception_max_capacity"]
            if class_row["exception_max_capacity"] is not None
            else class_row["max_capacity"]
        )

        class_history_id, _ = await self._materializer.find_or_create_history(
            class_id,
            gym_id,
            occurrence.occurred_at,
            occurrence.instructor_id,
            occurrence.duration_minutes,
        )

        return OccurrenceContext(
            class_history_id=class_history_id,
            class_id=class_id,
            gym_id=gym_id,
            occurred_at=occurrence.occurred_at,
            points_worth=class_row["points_worth"],
            class_name=class_row["class_name"],
            max_capacity=effective_capacity,
            allowed_plan_ids=self._parse_allowed_plan_ids(
                class_row["allowed_plan_ids"]
            ),
            instructor_id=occurrence.instructor_id,
            duration_minutes=occurrence.duration_minutes,
        )

    async def checkin_member(
        self,
        ctx: OccurrenceContext,
        member_id: UUID,
        allow_override: bool = False,
    ) -> CheckinResponse:
        """Gate + write one member against a resolved occurrence.

        Args:
            ctx: The resolved occurrence (from ``resolve_occurrence``).
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
            select_best_membership_forced(active)
            if allow_override
            else select_best_membership(active, eligible)
        )
        if chosen is None:
            breakdown = build_breakdown(active, eligible, None)
            return self._skipped(
                ctx, member_id, CheckinSkipReason.no_eligible_plan, breakdown
            )

        should_end = should_end_membership(chosen)

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
            memberships=build_breakdown(active, eligible, chosen.item_id),
        )

    # -- helpers ---------------------------------------------------------

    async def _expand_single_day(
        self,
        class_row: dict,
        class_id: UUID,
        occurrence_date: date,
        gym_tz: str,
    ) -> EffectiveOccurrence | None:
        """Run the expander over ``[date, date]`` and return the effective
        occurrence on that date (None when cancelled / not-a-recurrence-date).

        Loading instance + range exceptions for the single day and matching on
        ``effective_date`` gives the exception-applied time / instructor /
        duration and the gym-tz UTC ``occurred_at`` used to materialize.
        """
        instances = await self._queries.get_instance_exceptions(
            class_id, occurrence_date, occurrence_date
        )
        ranges = await self._queries.get_range_exceptions(
            class_id, occurrence_date, occurrence_date
        )
        occurrences = self._expander.expand(
            to_expander_class(class_row),
            [to_expander_instance(row) for row in instances],
            [to_expander_range(row) for row in ranges],
            occurrence_date,
            occurrence_date,
            gym_tz,
        )
        return next(
            (
                occ
                for occ in occurrences
                if occ.effective_date == occurrence_date
            ),
            None,
        )

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

    @staticmethod
    def _parse_allowed_plan_ids(raw: object) -> list[UUID] | None:
        """Coerce the JSONB allowed_plan_ids column to a UUID list.

        asyncpg may hand back JSONB as either a decoded list or a JSON string,
        so both are handled. None (the class allows every plan) stays None.
        """
        if raw is None:
            return None
        if isinstance(raw, str):
            raw = json.loads(raw)
        return [UUID(str(plan_id)) for plan_id in raw]

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
