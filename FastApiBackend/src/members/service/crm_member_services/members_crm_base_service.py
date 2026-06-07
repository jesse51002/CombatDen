"""Base service for CRM members list view services.

Provides shared query building logic inherited by
each view-specific service.
"""

from uuid import UUID

from schema.member_membership import MembershipDbStatus

import src.shared.db_schema_path  # noqa: F401
from src.members.schema.members_crm_members_list_schema import (
    CrmMemberStatus,
    MembersListFilters,
)
from src.shared.database import DirectDatabasePool

TERMINAL_STATUSES: frozenset[CrmMemberStatus] = frozenset(
    {CrmMemberStatus.cancelled, CrmMemberStatus.ended},
)
LIVE_DB_STATUSES: tuple[MembershipDbStatus, ...] = (
    MembershipDbStatus.active,
    MembershipDbStatus.frozen,
)


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

        where = "WHERE p.gym_id = :gym_id"
        if user_filters:
            where += " AND (" + " OR ".join(user_filters) + ")"

        if filters.name:
            where += " AND (p.first_name || ' ' || p.last_name ILIKE :name_search)"
            params["name_search"] = f"%{filters.name}%"

        return where, params

    def _apply_status_filter(
        self,
        statuses: list[CrmMemberStatus],
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
                CrmMemberStatus.overdue,
                CrmMemberStatus.trial,
                CrmMemberStatus.no_membership,
            )
        ]

        live_statuses = [v for v in db_statuses if v not in TERMINAL_STATUSES]
        terminal_statuses = [v for v in db_statuses if v in TERMINAL_STATUSES]

        if live_statuses:
            placeholders = ", ".join(f":status_{j}" for j in range(len(live_statuses)))
            conditions.append(f"m.status IN ({placeholders})")
            for j, v in enumerate(live_statuses):
                params[f"status_{j}"] = v.value

        if terminal_statuses:
            term_placeholders = ", ".join(
                f":term_status_{j}" for j in range(len(terminal_statuses))
            )
            live_placeholders = ", ".join(
                f":live_status_{j}" for j in range(len(LIVE_DB_STATUSES))
            )
            conditions.append(
                "("
                "EXISTS (SELECT 1 FROM member_memberships_status mm "
                "WHERE mm.member_id = p.member_id "
                "AND mm.gym_id = p.gym_id "
                f"AND mm.status IN ({term_placeholders})) "
                "AND NOT EXISTS (SELECT 1 FROM member_memberships_status mm "
                "WHERE mm.member_id = p.member_id "
                "AND mm.gym_id = p.gym_id "
                f"AND mm.status IN ({live_placeholders}))"
                ")",
            )
            for j, v in enumerate(terminal_statuses):
                params[f"term_status_{j}"] = v.value
            for j, v in enumerate(LIVE_DB_STATUSES):
                params[f"live_status_{j}"] = v.value

        if CrmMemberStatus.overdue in statuses:
            conditions.append("m.next_due_date < (now() AT TIME ZONE g.timezone)::date")

        if CrmMemberStatus.trial in statuses:
            conditions.append("mp.plan_type = 'trial'")

        if CrmMemberStatus.no_membership in statuses:
            conditions.append("m.status IS NULL")
