"""Per-member gate + write against a resolved class occurrence.

``checkin_member`` runs the per-member gate + write against a resolved
``ResolvedClass``, so a batch can resolve once then loop over members.

``is_member`` selects how the gate behaves:

* ``is_member=True`` (kiosk mode) — the strict gate: resolve
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

Both modes also run the **waiver gate**: a required waiver the member hasn't
signed at a current-enough version (the union of their active/frozen
memberships' plans' ``waiver_ids``, at the ``requires_resign`` floor — the
same set the member-detail Waivers section shows) rejects a kiosk check-in
and warns a staff one. Reservations (sign-ups) are deliberately NOT
waiver-gated — only the check-in.

Points are awarded on every newly-inserted attendance row regardless of
membership (a no-membership staff check-in still earns the class's points).
The gate evaluates the blocking conditions ONCE (relative to the attributed
"best available" membership); ``is_member`` decides block-vs-warn. Idempotent: a
repeat check-in for the same (member, class instance) returns the existing row
without consuming capacity, re-awarding points, or re-ending a membership.

**Membership coverage is evaluated at the OCCURRENCE'S instant, never at
now** (``resolved_class.occurred_at`` — the effective start). A retro
check-in attributes to the membership that covered THAT class: a trial that
has since ended still covers a class inside its window; a membership started
after the occurrence does not; a recurring plan's ``out_of_classes`` counts
usage in the billing cycle CONTAINING the occurrence, not the current one
(``CycleCountsService`` with ``reference_instant``). For a current occurrence
this degenerates exactly to the old now-anchored behavior. Known best-effort
limit: only the member's current/most recent freeze window is stored, so
historical freezes are invisible to the coverage test.
"""

from uuid import UUID

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.checkin.schema.checkin_schema import (
    CheckinMembershipBreakdown,
    CheckinResponse,
    CheckinWarning,
    GateEvaluation,
    ResolvedClass,
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
# hardest stops, then the unsigned-waiver legal gate, then punch-card
# depletion, then plan ineligibility.
_REASON_PRIORITY: tuple[CheckinWarning, ...] = (
    CheckinWarning.over_capacity,
    CheckinWarning.no_membership,
    CheckinWarning.unsigned_waiver,
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
        resolved_class: ResolvedClass,
        member_id: UUID,
        is_member: bool = False,
        ignore_warnings: bool = False,
    ) -> CheckinResponse:
        """Gate + write one member against a resolved occurrence.

        Args:
            resolved_class: The resolved class (from the class resolver).
            member_id: The member checking in.
            is_member: ``True`` for kiosk mode (strict gate
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
            member_id,
            resolved_class.class_id,
            resolved_class.occurrence_date,
            resolved_class.original_time,
        )
        if existing is not None:
            return self._already_checked_in(
                resolved_class,
                member_id,
                existing["log_id"],
                existing["plan_id"],
                existing["item_id"],
            )

        active = await self._active_memberships(member_id, resolved_class)
        eligible = (
            await self._queries.get_eligible_plans(
                resolved_class.gym_id, resolved_class.class_id, [m.plan_id for m in active]
            )
            if active
            else set()
        )
        over_capacity = await self._is_over_capacity(resolved_class, member_id)
        unsigned_waivers = await self._queries.get_unsigned_waivers(
            member_id, resolved_class.gym_id
        )
        evaluation = self._evaluate(
            active, eligible, over_capacity, bool(unsigned_waivers)
        )

        if is_member:
            return await self._checkin_kiosk(
                resolved_class, member_id, active, eligible, evaluation
            )
        return await self._checkin_staff(
            resolved_class, member_id, active, eligible, evaluation, ignore_warnings
        )

    # -- mode handlers ---------------------------------------------------

    async def _checkin_kiosk(
        self,
        resolved_class: ResolvedClass,
        member_id: UUID,
        active: list[MembershipUsage],
        eligible: set[UUID],
        evaluation: GateEvaluation,
    ) -> CheckinResponse:
        """Strict gate: reject when blocked, else record against ``strict``."""
        if evaluation.blocked:
            return self._skipped(
                resolved_class,
                member_id,
                self._primary_reason(evaluation.reasons),
                self._plan_selector.build_breakdown(active, eligible, None),
            )
        return await self._record(
            resolved_class, member_id, active, eligible, evaluation.strict, warnings=[]
        )

    async def _checkin_staff(
        self,
        resolved_class: ResolvedClass,
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
                resolved_class, member_id, active, eligible, warnings
            )
        return await self._record(
            resolved_class, member_id, active, eligible, evaluation.forced, warnings
        )

    def _needs_confirmation(
        self,
        resolved_class: ResolvedClass,
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
            class_id=resolved_class.class_id,
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
        resolved_class: ResolvedClass,
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
            resolved_class, member_id, plan_id, item_id, should_end
        )
        if already:
            return self._already_checked_in(
                resolved_class, member_id, log_id, plan_id, item_id
            )

        return CheckinResponse(
            log_id=log_id,
            member_id=member_id,
            class_id=resolved_class.class_id,
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
        has_unsigned_waiver: bool,
    ) -> GateEvaluation:
        """Evaluate the blocking conditions ONCE for both modes.

        ``reasons`` describe the attributed "best available" membership
        (``forced``) — depletion / ineligibility of the row a staff check-in
        draws down. ``strict`` (best eligible-with-capacity membership) drives
        the kiosk block decision; the two diverge only when a clean covering
        membership exists but a higher-priority pack is the staff attribution
        target, in which case the staff path warns while the kiosk path admits.
        The unsigned-waiver legal gate is membership-independent (flagged even
        when occurrence coverage is empty — it describes the member NOW).
        """
        evaluation = GateEvaluation()
        if over_capacity:
            evaluation.reasons.add(CheckinWarning.over_capacity)
        if has_unsigned_waiver:
            evaluation.reasons.add(CheckinWarning.unsigned_waiver)

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

    async def _is_over_capacity(
        self, resolved_class: ResolvedClass, member_id: UUID
    ) -> bool:
        """Whether checking THIS member in would exceed ``max_capacity``.

        Capacity is reserving: counts the DISTINCT signed-up-or-attended union
        (``class_signups`` ∪ ``member_attendance``) for THIS exact slot, not
        raw attendance — so a member already counted (a prior sign-up, or an
        idempotent repeat check-in) never blocks on their own presence, a
        same-day sibling occurrence's headcount never bleeds into this one's,
        and a fresh walk-in is blocked once the union fills the room.
        """
        if resolved_class.max_capacity is None:
            return False
        members = await self._queries.get_signup_or_attended_members(
            resolved_class.class_id,
            resolved_class.gym_id,
            resolved_class.occurrence_date,
            resolved_class.original_time,
        )
        if member_id in members:
            return False
        return len(members) >= resolved_class.max_capacity

    # -- helpers ---------------------------------------------------------

    async def _active_memberships(
        self,
        member_id: UUID,
        resolved_class: ResolvedClass,
    ) -> list[MembershipUsage]:
        """The member's memberships that COVERED the resolved occurrence,
        with usage counted in the cycle containing it.

        Coverage (``covers_reference``) is evaluated at the occurrence's
        effective start instant, not at now — the whole point of retro
        check-ins attributing correctly (see the module docstring). For a
        current occurrence this is exactly the old ``status == active``
        filter.
        """
        counts_request = CheckinCycleCountsRequest(
            gym_id=resolved_class.gym_id,
            member_ids=[member_id],
        )
        counts = await self._cycle_counts.get_cycle_counts(
            counts_request,
            reference_instant=resolved_class.occurred_at,
        )
        if not counts.users:
            return []
        return [
            m for m in counts.users[0].memberships if m.covers_reference
        ]

    def _already_checked_in(
        self,
        resolved_class: ResolvedClass,
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
            class_id=resolved_class.class_id,
            already_checked_in=True,
            chosen_plan_id=plan_id,
            chosen_item_id=item_id,
            points_awarded=resolved_class.points_worth,
            skip_reason=None,
            warnings=[],
            memberships=[],
        )

    def _skipped(
        self,
        resolved_class: ResolvedClass,
        member_id: UUID,
        reason: CheckinWarning,
        memberships: list[CheckinMembershipBreakdown],
    ) -> CheckinResponse:
        """Build a kiosk-rejected response (nothing written, no points)."""
        return CheckinResponse(
            log_id=None,
            member_id=member_id,
            class_id=resolved_class.class_id,
            already_checked_in=False,
            chosen_plan_id=None,
            chosen_item_id=None,
            points_awarded=0,
            skip_reason=reason,
            warnings=[],
            memberships=memberships,
        )
