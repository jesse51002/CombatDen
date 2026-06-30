"""Service for querying class usage per membership in the current billing cycle."""

from collections import defaultdict
from uuid import UUID

from schema.membership_plan import PlanType
from sqlalchemy import text

from src.checkin import SQL_DIR
from src.checkin.schema.cycle_counts_schema import (
    CheckinCycleCountsRequest,
    CheckinCycleCountsResponse,
    MembershipUsage,
    UserCycleCounts,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql


class CycleCountsService:
    """Counts classes used per membership within each plan's billing cycle.

    Args:
        db_pool: Injected database connection pool.
    """

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    async def get_cycle_counts(
        self,
        request: CheckinCycleCountsRequest,
    ) -> CheckinCycleCountsResponse:
        """Get current-cycle class usage for each membership.

        Args:
            request: Gym and member IDs to query.

        Returns:
            Per-user, per-membership usage with remaining capacity.
        """
        params = {
            "gym_id": str(request.gym_id),
            "member_ids": [str(uid) for uid in request.member_ids],
        }

        sql = load_sql(SQL_DIR / "classes_all_memberships.sql")

        async with self._db_pool.session() as session:
            result = await session.execute(text(sql), params)
            rows = result.mappings().all()

        return self._build_response(rows)

    @staticmethod
    def _build_response(rows: list) -> CheckinCycleCountsResponse:
        """Build structured response from combined query rows.

        Args:
            rows: SQL rows with membership info and classes_used.

        Returns:
            Structured response with remaining capacity computed.
        """
        user_memberships: dict[UUID, list[MembershipUsage]] = defaultdict(list)

        for row in rows:
            uid = row["member_id"]

            # classes_remaining is clamped at 0 (NULL stays NULL for unlimited)
            # by the SQL CASE/GREATEST, so an over-drawn pack never goes negative.
            user_memberships[uid].append(
                MembershipUsage(
                    item_id=row["item_id"],
                    plan_id=row["plan_id"],
                    start_date=row["start_date"],
                    plan_type=PlanType(row["plan_type"]),
                    status=row["status"],
                    class_count=row["class_count"],
                    classes_used=row["classes_used"],
                    classes_remaining=row["classes_remaining"],
                    renew_date=row["next_due_date"],
                    end_date=row["end_date"],
                )
            )

        users = [
            UserCycleCounts(member_id=uid, memberships=memberships)
            for uid, memberships in user_memberships.items()
        ]

        return CheckinCycleCountsResponse(users=users)
