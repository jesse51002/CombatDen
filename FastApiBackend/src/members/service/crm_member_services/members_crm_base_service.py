"""Base service for CRM members list view services.

Provides shared query building logic inherited by
each view-specific service.
"""

from uuid import UUID

from src.members.schema.members_crm_members_list_schema import (
    MembershipStatus,
    MembersListFilters,
)
from src.shared.database import DirectDatabasePool


class CrmBaseViewService:
    """Base class for CRM members list view services.

    Provides shared helpers for filtering and formatting.

    Args:
        db_pool: Injected database connection pool.
    """

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    # -- Filter builder --

    def build_where_clause(
        self,
        gym_id: UUID,
        filters: MembersListFilters,
    ) -> tuple[str, dict]:
        """Build a SQL WHERE clause from request filters.

        Args:
            gym_id: The gym to filter by.
            filters: Filters object with status and date range.

        Returns:
            Tuple of (WHERE clause string, params dict).
        """
        params: dict = {"gym_id": str(gym_id)}
        user_filters: list[str] = []

        if filters.membership_status:
            self._apply_status_filter(
                filters.membership_status,
                user_filters,
                params,
            )

        if filters.date_range:
            if filters.date_range.start_date:
                user_filters.append("m.start_date >= :date_start")
                params["date_start"] = filters.date_range.start_date.isoformat()
            if filters.date_range.end_date:
                user_filters.append("m.start_date <= :date_end")
                params["date_end"] = filters.date_range.end_date.isoformat()

        if filters.name:
            user_filters.append(
                "(p.first_name || ' ' || p.last_name ILIKE :name_search)",
            )
            params["name_search"] = f"%{filters.name}%"

        where = "WHERE p.gym_id = :gym_id"
        if user_filters:
            where += " AND (" + " OR ".join(user_filters) + ")"
        return where, params

    def _apply_status_filter(
        self,
        statuses: list[MembershipStatus],
        conditions: list[str],
        params: dict,
    ) -> None:
        """Apply membership status filter to the query.

        Handles 'overdue' specially since it's not a real DB
        status — it maps to members with an overdue
        next_due_date.

        Args:
            statuses: List of membership statuses to filter by.
            conditions: List of WHERE conditions to append to.
            params: Dict of query params to append to.
        """
        db_statuses = [
            v
            for v in statuses
            if v
            not in (
                MembershipStatus.overdue,
                MembershipStatus.trial,
                MembershipStatus.no_membership,
            )
        ]

        if db_statuses:
            placeholders = ", ".join(f":status_{j}" for j in range(len(db_statuses)))
            conditions.append(f"m.status IN ({placeholders})")
            for j, v in enumerate(db_statuses):
                params[f"status_{j}"] = v.value

        if MembershipStatus.overdue in statuses:
            conditions.append("m.next_due_date < CURRENT_DATE")

        if MembershipStatus.trial in statuses:
            conditions.append("mp.plan_type = 'trial'")

        if MembershipStatus.no_membership in statuses:
            conditions.append("m.status IS NULL")
