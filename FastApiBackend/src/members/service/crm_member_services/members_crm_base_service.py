"""Base service for CRM members list view services.

Provides shared query building and rank lookup
logic inherited by each view-specific service.
"""

from uuid import UUID

from src.members.schema.members_crm_members_list_schema import (
    MembershipStatus,
    MembersListFilters,
)
from src.shared.database import DirectDatabasePool


class CrmBaseViewService:
    """Base class for CRM members list view services.

    Provides shared helpers for filtering, formatting,
    and rank name resolution.

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
            filters: Filters object with status, rank,
                and date range.

        Returns:
            Tuple of (WHERE clause string, params dict).
        """
        conditions = ["p.gym_id = :gym_id"]
        params: dict = {"gym_id": str(gym_id)}

        if filters.membership_status:
            self._apply_status_filter(filters.membership_status, conditions, params)

        if filters.rank:
            placeholders = ", ".join(f":rank_{j}" for j in range(len(filters.rank)))
            conditions.append(f"p.current_rank IN ({placeholders})")
            for j, v in enumerate(filters.rank):
                params[f"rank_{j}"] = v

        if filters.date_range:
            if filters.date_range.start_date:
                conditions.append("m.start_date >= :date_start")
                params["date_start"] = filters.date_range.start_date.isoformat()
            if filters.date_range.end_date:
                conditions.append("m.start_date <= :date_end")
                params["date_end"] = filters.date_range.end_date.isoformat()

        if filters.name:
            conditions.append("(p.first_name || ' ' || p.last_name ILIKE :name_search)")
            params["name_search"] = f"%{filters.name}%"

        where = "WHERE " + " AND ".join(conditions)
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
        db_statuses = [v for v in statuses if v != MembershipStatus.overdue]

        if db_statuses:
            placeholders = ", ".join(f":status_{j}" for j in range(len(db_statuses)))
            conditions.append(f"m.status IN ({placeholders})")
            for j, v in enumerate(db_statuses):
                params[f"status_{j}"] = v.value

        if MembershipStatus.overdue in statuses:
            conditions.append("m.next_due_date < CURRENT_DATE")

    # -- Rank helpers --

    def get_rank_name(self, rank: int | None, row: dict) -> str | None:
        """Get the rank display name from gym config.

        Args:
            rank: The member's current rank (1-5) or None.
            row: Database row containing rank_N_name columns.

        Returns:
            Rank name string or None if no rank.
        """
        if not rank:
            return None
        return row.get(f"rank_{rank}_name")

    def get_estimated_classes_for_rank(self, rank: int | None, row: dict) -> int:
        """Get estimated classes needed for a rank level.

        Args:
            rank: The member's current rank (1-5) or None.
            row: Database row with estimated_classes_rank_N.

        Returns:
            Estimated class count, or 0 if rank is None.
        """
        if not rank:
            return 0
        return row.get(f"estimated_classes_rank_{rank}", 0)
