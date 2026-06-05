"""Service for checking a member into a class with automatic plan selection.

The check-in is gated, faithful to the original CRM: it resolves the member's
active memberships, computes per-cycle usage, gates by plan eligibility and
remaining capacity, selects the best covering plan (trial -> one_time ->
recurring, then lowest class_count first), logs the attendance against that
membership, and auto-ends trial / punch-card memberships once depleted. If no
plan covers the class with capacity, the check-in is rejected and nothing is
written. Idempotent: a repeat check-in for the same (member, class instance)
returns the existing row without consuming capacity or re-ending a membership.
"""

from uuid import UUID

from schema.member_membership import MembershipDbStatus
from schema.membership_plan import PlanType
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.classes import SQL_DIR
from src.classes.schema.classes_cycle_counts_schema import (
    ClassesCycleCountsRequest,
    MembershipUsage,
)
from src.classes.schema.classes_plan_type import PlanInfo
from src.classes.schema.classes_schema import (
    CheckinMembershipBreakdown,
    CheckinRequest,
    CheckinResponse,
)
from src.classes.service.classes_cycle_counts_service import (
    ClassesCycleCountsService,
)
from src.shared.database import DirectDatabasePool
from src.shared.gym_timezone import gym_today
from src.shared.sql_loader import load_sql

_PLAN_TYPE_PRIORITY: dict[PlanType, int] = {
    PlanType.trial: 0,
    PlanType.recurring: 1,
    PlanType.one_time: 2,
}

_UNLIMITED = float("inf")

_FALLBACK_TIMEZONE = "America/Chicago"


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
        self._db_pool = db_pool
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
        class_id = await self._resolve_class_id(request)
        if class_id is None:
            raise ValueError(f"class_history_id {request.class_history_id} not found")

        existing = await self._get_existing_attendance(request)
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

        eligible = await self._get_eligible_plans(
            request.gym_id,
            class_id,
            [m.plan_id for m in active],
        )
        chosen_plan_id = self._select_best_plan(active, eligible)
        if chosen_plan_id is None:
            breakdown = self._build_breakdown(active, eligible, None)
            return self._rejected(request, breakdown)

        item_id = await self._resolve_item_id(request, chosen_plan_id)
        if item_id is None:
            breakdown = self._build_breakdown(active, eligible, None)
            return self._rejected(request, breakdown)

        chosen = next(m for m in active if m.plan_id == chosen_plan_id)
        should_end = self._should_end_membership(chosen)

        log_id, already = await self._write_checkin(
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
            memberships=self._build_breakdown(active, eligible, chosen_plan_id),
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

    async def _resolve_class_id(
        self,
        request: CheckinRequest,
    ) -> UUID | None:
        """Resolve the class a class_history occurrence belongs to."""
        sql = load_sql(SQL_DIR / "resolve_class.sql")
        async with self._db_pool.session() as session:
            row = (
                (
                    await session.execute(
                        text(sql),
                        {
                            "class_history_id": str(request.class_history_id),
                            "gym_id": str(request.gym_id),
                        },
                    )
                )
                .mappings()
                .fetchone()
            )
        return row["class_id"] if row else None

    async def _get_existing_attendance(
        self,
        request: CheckinRequest,
    ) -> dict | None:
        """Return the existing attendance row, if any (idempotency)."""
        sql = load_sql(SQL_DIR / "get_existing_attendance.sql")
        async with self._db_pool.session() as session:
            row = (
                (
                    await session.execute(
                        text(sql),
                        {
                            "member_id": str(request.member_id),
                            "class_history_id": str(request.class_history_id),
                        },
                    )
                )
                .mappings()
                .fetchone()
            )
        return dict(row) if row else None

    async def _get_eligible_plans(
        self,
        gym_id: UUID,
        class_id: UUID,
        plan_ids: list[UUID],
    ) -> set[UUID]:
        """Query which of the plans may attend the given class."""
        sql = load_sql(SQL_DIR / "class_plan_eligibility.sql")
        async with self._db_pool.session() as session:
            rows = (
                (
                    await session.execute(
                        text(sql),
                        {
                            "gym_id": str(gym_id),
                            "class_id": str(class_id),
                            "plan_ids": [str(pid) for pid in plan_ids],
                        },
                    )
                )
                .mappings()
                .all()
            )
        return {row["plan_id"] for row in rows}

    async def _resolve_item_id(
        self,
        request: CheckinRequest,
        plan_id: UUID,
    ) -> UUID | None:
        """Pick the concrete active membership row to charge for a plan."""
        sql = load_sql(SQL_DIR / "select_membership_item.sql")
        async with self._db_pool.session() as session:
            row = (
                (
                    await session.execute(
                        text(sql),
                        {
                            "member_id": str(request.member_id),
                            "gym_id": str(request.gym_id),
                            "plan_id": str(plan_id),
                        },
                    )
                )
                .mappings()
                .fetchone()
            )
        return row["item_id"] if row else None

    async def _write_checkin(
        self,
        request: CheckinRequest,
        plan_id: UUID,
        item_id: UUID,
        should_end: bool,
    ) -> tuple[UUID, bool]:
        """Insert attendance, bump last_class, and conditionally auto-end.

        Returns:
            (log_id, already_checked_in). already_checked_in is True only
            when a concurrent check-in won the INSERT race; in that case no
            auto-end is performed.
        """
        insert_sql = load_sql(SQL_DIR / "insert_attendance.sql")
        existing_sql = load_sql(SQL_DIR / "get_existing_attendance.sql")
        last_class_sql = load_sql(SQL_DIR / "update_last_class.sql")

        async with self._db_pool.session() as session:
            insert_row = (
                (
                    await session.execute(
                        text(insert_sql),
                        {
                            "member_id": str(request.member_id),
                            "gym_id": str(request.gym_id),
                            "class_history_id": str(request.class_history_id),
                            "plan_id": str(plan_id),
                            "item_id": str(item_id),
                        },
                    )
                )
                .mappings()
                .fetchone()
            )

            if not insert_row:
                existing = (
                    (
                        await session.execute(
                            text(existing_sql),
                            {
                                "member_id": str(request.member_id),
                                "class_history_id": str(request.class_history_id),
                            },
                        )
                    )
                    .mappings()
                    .fetchone()
                )
                if not existing:
                    raise RuntimeError("Attendance row missing after ON CONFLICT DO NOTHING")
                await session.commit()
                return existing["log_id"], True

            log_id: UUID = insert_row["log_id"]

            await session.execute(
                text(last_class_sql),
                {
                    "member_id": str(request.member_id),
                    "class_history_id": str(request.class_history_id),
                },
            )

            if should_end:
                await self._end_membership(session, request, item_id)

            await session.commit()
            return log_id, False

    async def _end_membership(
        self,
        session,
        request: CheckinRequest,
        item_id: UUID,
    ) -> None:
        """Set end_date on the charged membership to end it (within session)."""
        tz_sql = load_sql(SQL_DIR / "get_gym_timezone.sql")
        end_sql = load_sql(SQL_DIR / "end_membership.sql")

        tz_row = (
            (
                await session.execute(
                    text(tz_sql),
                    {"gym_id": str(request.gym_id)},
                )
            )
            .mappings()
            .fetchone()
        )
        timezone = tz_row["timezone"] if tz_row else _FALLBACK_TIMEZONE

        await session.execute(
            text(end_sql),
            {
                "item_id": str(item_id),
                "member_id": str(request.member_id),
                "end_date": gym_today(timezone),
            },
        )

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

    @staticmethod
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

    @classmethod
    def _select_best_plan(
        cls,
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

        return cls._sort_plans_by_priority(candidates)[0].plan_id

    @staticmethod
    def _should_end_membership(membership: MembershipUsage) -> bool:
        """Trial and one_time plans end when their last class is used.

        Recurring and unlimited plans never auto-end.
        """
        if membership.plan_type == PlanType.recurring:
            return False
        if membership.class_count is None:
            return False
        return membership.classes_used + 1 >= membership.class_count

    @staticmethod
    def _build_breakdown(
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
                )
            )
        return result
