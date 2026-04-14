"""Service for checking a member into a class with automatic plan selection."""

from uuid import UUID

from schema.member_membership import MembershipDbStatus
from sqlalchemy import text

from src.classes import SQL_DIR
from src.classes.schema.classes_checkin_schema import (
    CheckinMembershipBreakdown,
    ClassesCheckinRequest,
    ClassesCheckinResponse,
)
from src.classes.schema.classes_cycle_counts_schema import (
    ClassesCycleCountsRequest,
    MembershipUsage,
)
from src.classes.schema.classes_plan_type import PlanInfo, PlanType
from src.classes.service.classes_cycle_counts_service import (
    ClassesCycleCountsService,
)
from src.shared.database import DirectDatabasePool
from src.shared.gym_timezone import gym_today
from src.shared.sql_loader import load_sql

_PLAN_TYPE_PRIORITY: dict[PlanType, int] = {
    PlanType.trial: 0,
    PlanType.one_time: 1,
    PlanType.recurring: 2,
}

_UNLIMITED = float("inf")


def _sort_plans_by_priority(plans: list[PlanInfo]) -> list[PlanInfo]:
    """Sort plans by type priority then by class_count ascending.

    Order: trial -> one_time -> recurring.
    Within the same type, lower class_count first (unlimited last).

    Args:
        plans: List of plan metadata to sort.

    Returns:
        A new list sorted by priority.
    """
    return sorted(
        plans,
        key=lambda p: (
            _PLAN_TYPE_PRIORITY[p.plan_type],
            p.class_count if p.class_count is not None else _UNLIMITED,
        ),
    )


class ClassesCheckinService:
    """Checks a member into a class, selecting the best membership plan.

    Priority: trial -> one_time -> recurring, then lower class_count
    first. Only eligible plans with remaining capacity are considered.

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

    async def checkin(
        self,
        request: ClassesCheckinRequest,
    ) -> ClassesCheckinResponse:
        """Check a member into a class.

        Selects the best eligible membership, inserts a log entry,
        and returns a full breakdown of all active memberships.
        If no eligible plan is found, returns a response with
        None for log_id and chosen_plan_id so the frontend can
        display an appropriate message.

        Args:
            request: Member, gym, and class identifiers.

        Returns:
            Check-in result with chosen plan and usage breakdown.
        """
        counts_request = ClassesCycleCountsRequest(
            gym_id=request.gym_id,
            crm_user_ids=[request.crm_user_id],
        )
        counts_response = await self._cycle_counts.get_cycle_counts(counts_request)

        if not counts_response.users:
            return ClassesCheckinResponse(
                log_id=None,
                chosen_plan_id=None,
                memberships=[],
            )

        all_memberships = counts_response.users[0].memberships
        active_memberships = [m for m in all_memberships if m.status == MembershipDbStatus.active]

        if not active_memberships:
            return ClassesCheckinResponse(
                log_id=None,
                chosen_plan_id=None,
                memberships=[],
            )

        eligible_plan_ids = await self._get_eligible_plans(
            request.gym_id,
            request.class_id,
            [m.plan_id for m in active_memberships],
        )

        chosen_plan_id = self._select_best_plan(
            active_memberships,
            eligible_plan_ids,
        )

        if chosen_plan_id is None:
            memberships = self._build_breakdown(
                active_memberships,
                eligible_plan_ids,
                None,
            )
            return ClassesCheckinResponse(
                log_id=None,
                chosen_plan_id=None,
                memberships=memberships,
            )

        log_id = await self._insert_log(request, chosen_plan_id)
        await self._update_last_class(request)

        chosen_membership = next(m for m in active_memberships if m.plan_id == chosen_plan_id)
        if self._should_end_membership(chosen_membership):
            await self._end_membership(request, chosen_plan_id)

        memberships = self._build_breakdown(
            active_memberships,
            eligible_plan_ids,
            chosen_plan_id,
        )

        return ClassesCheckinResponse(
            log_id=log_id,
            chosen_plan_id=chosen_plan_id,
            memberships=memberships,
        )

    async def _get_eligible_plans(
        self,
        gym_id: UUID,
        class_id: UUID,
        plan_ids: list[UUID],
    ) -> set[UUID]:
        """Query which plans are eligible for a specific class.

        Args:
            gym_id: The gym.
            class_id: The class to check.
            plan_ids: Plans to check eligibility for.

        Returns:
            Set of plan_ids eligible for the given class.
        """
        eligibility_sql = load_sql(SQL_DIR / "class_plan_eligibility.sql")

        async with self._db_pool.session() as session:
            elig_rows = (
                (
                    await session.execute(
                        text(eligibility_sql),
                        {
                            "gym_id": str(gym_id),
                            "plan_ids": [str(pid) for pid in plan_ids],
                        },
                    )
                )
                .mappings()
                .all()
            )

        eligible: set[UUID] = set()
        for row in elig_rows:
            if row["class_id"] == class_id:
                eligible.add(row["plan_id"])
        return eligible

    async def _insert_log(
        self,
        request: ClassesCheckinRequest,
        plan_id: UUID,
    ) -> UUID:
        """Insert a gym_classes_log entry.

        Args:
            request: The checkin request.
            plan_id: The chosen plan to log against.

        Returns:
            The new log_id.
        """
        insert_sql = load_sql(SQL_DIR / "classes_checkin_insert.sql")

        async with self._db_pool.session() as session:
            result = await session.execute(
                text(insert_sql),
                {
                    "crm_user_id": str(request.crm_user_id),
                    "gym_id": str(request.gym_id),
                    "class_id": str(request.class_id),
                    "plan_id": str(plan_id),
                },
            )
            log_id = result.scalar_one()
            await session.commit()

        return log_id

    async def _update_last_class(
        self,
        request: ClassesCheckinRequest,
    ) -> None:
        """Update the member's last_class timestamp on their profile.

        Args:
            request: The checkin request with user/gym identifiers.
        """
        update_sql = load_sql(SQL_DIR / "classes_checkin_update_last_class.sql")

        async with self._db_pool.session() as session:
            await session.execute(
                text(update_sql),
                {
                    "crm_user_id": str(request.crm_user_id),
                    "gym_id": str(request.gym_id),
                },
            )
            await session.commit()

    @staticmethod
    def _select_best_plan(
        memberships: list[MembershipUsage],
        eligible_plan_ids: set[UUID],
    ) -> UUID | None:
        """Select the best eligible plan with remaining capacity.

        Args:
            memberships: Active memberships with usage.
            eligible_plan_ids: Plans that cover this class.

        Returns:
            The plan_id to charge, or None if no eligible plan
            has capacity.
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

        sorted_plans = _sort_plans_by_priority(candidates)
        return sorted_plans[0].plan_id

    @staticmethod
    def _should_end_membership(membership: MembershipUsage) -> bool:
        """Check if a membership should be ended after this check-in.

        Trial and one-time plans end when all classes are used up.

        Args:
            membership: The membership that was just charged.

        Returns:
            True if the membership should be ended.
        """
        if membership.plan_type == PlanType.recurring:
            return False
        if membership.class_count is None:
            return False
        return membership.classes_used + 1 >= membership.class_count

    async def _end_membership(
        self,
        request: ClassesCheckinRequest,
        plan_id: UUID,
    ) -> None:
        """Set end_date on a membership to end it.

        Args:
            request: The checkin request with user/gym identifiers.
            plan_id: The plan to end.
        """
        end_sql = load_sql(SQL_DIR / "classes_checkin_end_membership.sql")

        async with self._db_pool.session() as session:
            tz_result = await session.execute(
                text("SELECT timezone FROM gyms WHERE gym_id = :gym_id"),
                {"gym_id": str(request.gym_id)},
            )
            tz_row = tz_result.mappings().fetchone()
            end_date = gym_today(tz_row["timezone"]) if tz_row else gym_today("America/Chicago")

            await session.execute(
                text(end_sql),
                {
                    "crm_user_id": str(request.crm_user_id),
                    "gym_id": str(request.gym_id),
                    "plan_id": str(plan_id),
                    "end_date": end_date,
                },
            )
            await session.commit()

    @staticmethod
    def _build_breakdown(
        memberships: list[MembershipUsage],
        eligible_plan_ids: set[UUID],
        chosen_plan_id: UUID | None,
    ) -> list[CheckinMembershipBreakdown]:
        """Build the full membership breakdown for the response.

        Increments the chosen plan's usage by 1 to reflect
        the just-inserted check-in.

        Args:
            memberships: Active memberships with pre-checkin usage.
            eligible_plan_ids: Plans that cover the class.
            chosen_plan_id: The plan that was charged.

        Returns:
            Breakdown of all active memberships post-checkin.
        """
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
