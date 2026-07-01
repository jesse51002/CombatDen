"""Per-member gate + write against a resolved class occurrence.

``checkin_member`` runs the per-member gate + write against a resolved
``OccurrenceContext``, so a batch can resolve once then loop over members.

``is_member`` selects how the gate behaves:

* ``is_member=True`` (kiosk / member self-check-in) — the strict gate: resolve
  the member's active memberships, gate by plan eligibility + remaining
  punch-card capacity + the room's ``max_capacity``, and check in against the
  best covering plan (trial -> one_time -> recurring, then lowest class_count,
  then oldest pack). If no eligible covering membership has capacity, the room
  is full, or the member has no membership, the check-in is *rejected* (skipped,
  ``log_id`` None, with a ``skip_reason``); nothing is written.
* ``is_member=False`` (staff / admin — the default) — the check-in is ALWAYS
  recorded. It is attributed to the member's best available membership via
  ``select_best_membership_forced`` (eligibility + remaining count ignored, an
  over-draw allowed); with no active membership the attendance is written with
  NULL ``plan_id`` / ``item_id``. Every condition that would have blocked a
  kiosk check-in is returned as a ``warnings`` entry instead of blocking.

Points are awarded on every newly-inserted attendance row regardless of
membership (a no-membership staff check-in still earns the class's points).
The gate evaluates the blocking conditions ONCE (relative to the attributed
"best available" membership); ``is_member`` decides block-vs-warn. Idempotent: a
repeat check-in for the same (member, class instance) returns the existing row
without consuming capacity, re-awarding points, or re-ending a membership.
"""

from uuid import UUID

from schema.member_membership import MembershipDbStatus

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.checkin.schema.checkin_schema import (
    CheckinMembershipBreakdown,
    CheckinResponse,
    CheckinWarning,
    GateEvaluation,
    OccurrenceContext,
)
from src.checkin.schema.cycle_counts_schema import (
    CheckinCycleCountsRequest,
    MembershipUsage,
)
from src.checkin.service.checkin_plan_selector import CheckinPlanSelector
from src.checkin.service.checkin_queries import CheckinQueries
from src.checkin.service.checkin_writer import CheckinWriter
from src.checkin.service.cycle_counts_service import CycleCountsService
from src.shared.database import DirectDatabasePool

# Order a set of blocking reasons into a single primary ``skip_reason`` for a
# rejected kiosk check-in: the room being full and a missing membership are the
# hardest stops, then punch-card depletion, then plan ineligibility.
_REASON_PRIORITY: tuple[CheckinWarning, ...] = (
    CheckinWarning.over_capacity,
    CheckinWarning.no_membership,
    CheckinWarning.out_of_classes,
    CheckinWarning.ineligible_plan,
)


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
        is_member: bool = False,
        ignore_warnings: bool = False,
    ) -> CheckinResponse:
        """Gate + write one member against a resolved occurrence.

        Args:
            ctx: The resolved occurrence (from the occurrence resolver).
            member_id: The member checking in.
            is_member: ``True`` for a kiosk / member self-check-in (strict gate
                — reject when uncovered / full); ``False`` (default) for a staff
                check-in.
            ignore_warnings: Staff override. When ``False`` (default) a staff
                check-in that raises any warning is NOT recorded — it returns
                ``requires_confirmation`` with the warnings; ``True`` records it
                anyway. Ignored for a kiosk check-in.

        Returns:
            The check-in result — recorded, an idempotent repeat, a rejected
            kiosk skip, or a staff check-in held for confirmation
            (``requires_confirmation``).
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

        active = await self._active_memberships(member_id, ctx.gym_id)
        eligible = (
            await self._queries.get_eligible_plans(
                ctx.gym_id, ctx.class_id, [m.plan_id for m in active]
            )
            if active
            else set()
        )
        over_capacity = await self._is_over_capacity(ctx)
        evaluation = self._evaluate(active, eligible, over_capacity)

        if is_member:
            return await self._checkin_kiosk(
                ctx, member_id, active, eligible, evaluation
            )
        return await self._checkin_staff(
            ctx, member_id, active, eligible, evaluation, ignore_warnings
        )

    # -- mode handlers ---------------------------------------------------

    async def _checkin_kiosk(
        self,
        ctx: OccurrenceContext,
        member_id: UUID,
        active: list[MembershipUsage],
        eligible: set[UUID],
        evaluation: GateEvaluation,
    ) -> CheckinResponse:
        """Strict gate: reject when blocked, else record against ``strict``."""
        if evaluation.blocked:
            return self._skipped(
                ctx,
                member_id,
                self._primary_reason(evaluation.reasons),
                self._plan_selector.build_breakdown(active, eligible, None),
            )
        return await self._record(
            ctx, member_id, active, eligible, evaluation.strict, warnings=[]
        )

    async def _checkin_staff(
        self,
        ctx: OccurrenceContext,
        member_id: UUID,
        active: list[MembershipUsage],
        eligible: set[UUID],
        evaluation: GateEvaluation,
        ignore_warnings: bool,
    ) -> CheckinResponse:
        """Record a clean staff check-in. When the gate raised any warning, DON'T
        record unless ``ignore_warnings`` overrides — return the warnings for
        confirmation so staff can decide, then resend with the override."""
        warnings = sorted(
            evaluation.reasons, key=_REASON_PRIORITY.index
        )
        if warnings and not ignore_warnings:
            return self._needs_confirmation(
                ctx, member_id, active, eligible, warnings
            )
        return await self._record(
            ctx, member_id, active, eligible, evaluation.forced, warnings
        )

    def _needs_confirmation(
        self,
        ctx: OccurrenceContext,
        member_id: UUID,
        active: list[MembershipUsage],
        eligible: set[UUID],
        warnings: list[CheckinWarning],
    ) -> CheckinResponse:
        """A staff check-in held for confirmation: nothing is written; the
        warnings come back so staff can resend with ``ignore_warnings`` to
        record it."""
        return CheckinResponse(
            log_id=None,
            member_id=member_id,
            class_history_id=ctx.class_history_id,
            class_id=ctx.class_id,
            already_checked_in=False,
            chosen_plan_id=None,
            chosen_item_id=None,
            points_awarded=0,
            skip_reason=None,
            warnings=warnings,
            requires_confirmation=True,
            memberships=self._plan_selector.build_breakdown(
                active, eligible, None
            ),
        )

    async def _record(
        self,
        ctx: OccurrenceContext,
        member_id: UUID,
        active: list[MembershipUsage],
        eligible: set[UUID],
        chosen: MembershipUsage | None,
        warnings: list[CheckinWarning],
    ) -> CheckinResponse:
        """Write the attendance (NULL attribution when ``chosen`` is None) and
        build the recorded / idempotent-repeat response."""
        plan_id = chosen.plan_id if chosen is not None else None
        item_id = chosen.item_id if chosen is not None else None
        should_end = (
            self._plan_selector.should_end_membership(chosen)
            if chosen is not None
            else False
        )

        log_id, already, points = await self._writer.write_checkin(
            ctx, member_id, plan_id, item_id, should_end
        )
        if already:
            return self._already_checked_in(
                ctx, member_id, log_id, plan_id, item_id
            )

        return CheckinResponse(
            log_id=log_id,
            member_id=member_id,
            class_history_id=ctx.class_history_id,
            class_id=ctx.class_id,
            already_checked_in=False,
            chosen_plan_id=plan_id,
            chosen_item_id=item_id,
            points_awarded=points,
            skip_reason=None,
            warnings=warnings,
            memberships=self._plan_selector.build_breakdown(
                active, eligible, item_id
            ),
        )

    # -- gate evaluation -------------------------------------------------

    def _evaluate(
        self,
        active: list[MembershipUsage],
        eligible: set[UUID],
        over_capacity: bool,
    ) -> GateEvaluation:
        """Evaluate the blocking conditions ONCE for both modes.

        ``reasons`` describe the attributed "best available" membership
        (``forced``) — depletion / ineligibility of the row a staff check-in
        draws down. ``strict`` (best eligible-with-capacity membership) drives
        the kiosk block decision; the two diverge only when a clean covering
        membership exists but a higher-priority pack is the staff attribution
        target, in which case the staff path warns while the kiosk path admits.
        """
        evaluation = GateEvaluation()
        if over_capacity:
            evaluation.reasons.add(CheckinWarning.over_capacity)

        if not active:
            evaluation.reasons.add(CheckinWarning.no_membership)
            return evaluation

        evaluation.strict = self._plan_selector.select_best_membership(
            active, eligible
        )
        evaluation.forced = self._plan_selector.select_best_membership_forced(
            active
        )
        self._add_membership_reasons(evaluation.forced, eligible, evaluation)
        return evaluation

    @staticmethod
    def _add_membership_reasons(
        forced: MembershipUsage | None,
        eligible: set[UUID],
        evaluation: GateEvaluation,
    ) -> None:
        """Flag ineligibility / depletion of the attribution target."""
        if forced is None:
            return
        if forced.plan_id not in eligible:
            evaluation.reasons.add(CheckinWarning.ineligible_plan)
        if (
            forced.class_count is not None
            and forced.classes_used >= forced.class_count
        ):
            evaluation.reasons.add(CheckinWarning.out_of_classes)

    @staticmethod
    def _primary_reason(reasons: set[CheckinWarning]) -> CheckinWarning:
        """Pick the single ``skip_reason`` for a rejected kiosk check-in."""
        return min(reasons, key=_REASON_PRIORITY.index)

    async def _is_over_capacity(self, ctx: OccurrenceContext) -> bool:
        """Whether the room is at / over ``max_capacity`` for this occurrence."""
        if ctx.max_capacity is None:
            return False
        count = await self._queries.count_attendance(ctx.class_history_id)
        return count >= ctx.max_capacity

    # -- helpers ---------------------------------------------------------

    async def _active_memberships(
        self,
        member_id: UUID,
        gym_id: UUID,
    ) -> list[MembershipUsage]:
        """Return the member's active memberships with current usage."""
        counts_request = CheckinCycleCountsRequest(
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
        plan_id: UUID | None,
        item_id: UUID | None,
    ) -> CheckinResponse:
        """Build the idempotent-repeat response.

        No points are re-awarded (the balance is untouched), but
        ``points_awarded`` reports the class's ``points_worth`` — the amount this
        check-in was originally worth — so the caller can still show it for
        clarity, told apart from a fresh award by ``already_checked_in``.
        """
        return CheckinResponse(
            log_id=log_id,
            member_id=member_id,
            class_history_id=ctx.class_history_id,
            class_id=ctx.class_id,
            already_checked_in=True,
            chosen_plan_id=plan_id,
            chosen_item_id=item_id,
            points_awarded=ctx.points_worth,
            skip_reason=None,
            warnings=[],
            memberships=[],
        )

    def _skipped(
        self,
        ctx: OccurrenceContext,
        member_id: UUID,
        reason: CheckinWarning,
        memberships: list[CheckinMembershipBreakdown],
    ) -> CheckinResponse:
        """Build a kiosk-rejected response (nothing written, no points)."""
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
            warnings=[],
            memberships=memberships,
        )
