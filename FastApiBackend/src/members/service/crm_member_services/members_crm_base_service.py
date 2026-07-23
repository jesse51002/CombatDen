"""Base service for CRM members list view services.

Provides shared query building logic inherited by
each view-specific service.
"""

from uuid import UUID

from schema.member_membership import MembershipDbStatus
from schema.membership_plan import PlanType

import src.shared.db_schema_path  # noqa: F401
from src.members.schema.members_crm_members_list_schema import (
    CrmMemberStatus,
    MembersListFilters,
)
from src.members.service.members_status_mapping import (
    load_member_dormant_sql,
)
from src.shared.database import DirectDatabasePool

TERMINAL_STATUSES: frozenset[CrmMemberStatus] = frozenset(
    {CrmMemberStatus.cancelled, CrmMemberStatus.ended},
)
LIVE_DB_STATUSES: tuple[MembershipDbStatus, ...] = (
    MembershipDbStatus.active,
    MembershipDbStatus.frozen,
)
# The gym's local current date — every status predicate that depends on
# "today" (overdue / not-overdue) reads it off the joined `gyms g`.
GYM_TODAY_SQL = "(now() AT TIME ZONE g.timezone)::date"
# Every view aliases members as `p`, so the shared dormancy predicate is
# correlated to the same two id expressions everywhere.
DORMANT_SQL = load_member_dormant_sql("p.member_id", "p.gym_id")


class CrmBaseViewService:
    """Base class for CRM members list view services.

    Provides shared helpers for filtering and formatting.

    Args:
        db_pool: Injected database connection pool.
        dormancy_days: How long without activity makes a short-plan
            member dormant (``settings.member_dormancy_days``).
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        dormancy_days: int,
    ) -> None:
        self._db_pool = db_pool
        self._dormancy_days = dormancy_days

    # -- Filter builder --

    def build_where_clause(
        self,
        gym_id: UUID,
        filters: MembersListFilters,
    ) -> tuple[str, dict]:
        """Build a SQL WHERE clause from request filters.

        Each filter dimension narrows the result independently
        (the dimensions are AND-combined). Within the status
        dimension the selected statuses widen it (OR-combined),
        and plan_ids / rank_ids likewise match members holding
        any of the given plans / currently at any of the given
        ranks.

        Args:
            gym_id: The gym to filter by.
            filters: Filters object with status, plans, ranks,
                date range, and name.

        Returns:
            Tuple of (WHERE clause string, params dict).
        """
        params: dict = {"gym_id": str(gym_id)}
        clauses: list[str] = ["p.gym_id = :gym_id"]

        if filters.membership_status:
            status_conditions: list[str] = []
            self._apply_status_filter(
                filters.membership_status,
                status_conditions,
                params,
            )
            if status_conditions:
                clauses.append("(" + " OR ".join(status_conditions) + ")")

        if filters.plan_ids:
            placeholders = ", ".join(
                f":plan_{j}" for j in range(len(filters.plan_ids))
            )
            live_placeholders = ", ".join(
                f":plan_live_{j}" for j in range(len(LIVE_DB_STATUSES))
            )
            # A plan filter means members who currently hold the plan, so it
            # is scoped to LIVE memberships (active or frozen). A cancelled
            # or ended membership on the plan does not match.
            clauses.append(
                f"(mp.plan_id IN ({placeholders}) "
                f"AND m.status IN ({live_placeholders}))"
            )
            for j, plan_id in enumerate(filters.plan_ids):
                params[f"plan_{j}"] = str(plan_id)
            for j, live_status in enumerate(LIVE_DB_STATUSES):
                params[f"plan_live_{j}"] = live_status.value

        if filters.rank_ids:
            clauses.append(
                "p.current_rank_id = ANY(CAST(:rank_ids AS UUID[]))"
            )
            params["rank_ids"] = [str(rank_id) for rank_id in filters.rank_ids]

        if filters.date_range:
            if filters.date_range.start_date:
                clauses.append("m.start_date >= :date_start")
                params["date_start"] = filters.date_range.start_date.isoformat()
            if filters.date_range.end_date:
                clauses.append("m.start_date <= :date_end")
                params["date_end"] = filters.date_range.end_date.isoformat()

        if filters.name:
            clauses.append(
                "(p.first_name || ' ' || p.last_name ILIKE :name_search)"
            )
            params["name_search"] = f"%{filters.name}%"

        where = "WHERE " + " AND ".join(clauses)
        return where, params

    def _apply_status_filter(
        self,
        statuses: list[CrmMemberStatus],
        conditions: list[str],
        params: dict,
    ) -> None:
        """Append one OR-able predicate per selected DISPLAY status.

        The dialog's statuses are the DERIVED labels the CRM shows as
        badges (active / trial / overdue / no_membership on top of the
        raw DB active / frozen / cancelled / ended), so each predicate
        matches what the badge means, not the raw status column:

        - active: a paid, non-trial membership that is not past due
        - trial: an active trial that is not past due
        - overdue: a non-cancelled membership past its due date
        - frozen: a frozen membership
        - dormant: only short live packs + gone quiet, on a row that is
          live and not past due — a member-level check
        - cancelled / ended: the member's only memberships are terminal
          (no live one) — a member-level check
        - no_membership: the member has no membership row

        Args:
            statuses: Display statuses to filter by.
            conditions: List of WHERE conditions to append to.
            params: Dict of query params to append to.
        """
        not_overdue = (
            "(m.next_due_date IS NULL "
            f"OR m.next_due_date >= {GYM_TODAY_SQL})"
        )

        if CrmMemberStatus.active in statuses:
            conditions.append(
                "(m.status = :st_active AND mp.plan_type != :pt_trial "
                f"AND {not_overdue})"
            )
            params["st_active"] = MembershipDbStatus.active.value
            params["pt_trial"] = PlanType.trial.value

        if CrmMemberStatus.trial in statuses:
            conditions.append(
                "(mp.plan_type = :pt_trial AND m.status = :st_active "
                f"AND {not_overdue})"
            )
            params["pt_trial"] = PlanType.trial.value
            params["st_active"] = MembershipDbStatus.active.value

        if CrmMemberStatus.frozen in statuses:
            conditions.append("(m.status = :st_frozen)")
            params["st_frozen"] = MembershipDbStatus.frozen.value

        if CrmMemberStatus.overdue in statuses:
            conditions.append(
                "(m.status != :st_cancelled "
                f"AND m.next_due_date < {GYM_TODAY_SQL})"
            )
            params["st_cancelled"] = MembershipDbStatus.cancelled.value

        if CrmMemberStatus.dormant in statuses:
            # Matches exactly when the dormant badge renders: the member
            # is dormant AND this row is the kind of row that shows it.
            # Overdue and frozen outrank dormant (see DORMANT_YIELDS_TO
            # in members_status_mapping), and a terminal row never
            # carries it — so the row must be active and not past due.
            conditions.append(
                f"({DORMANT_SQL} AND m.status = :st_active_dormant "
                f"AND {not_overdue})"
            )
            params["st_active_dormant"] = MembershipDbStatus.active.value
            params["dormancy_days"] = self._dormancy_days

        if CrmMemberStatus.no_membership in statuses:
            conditions.append("(m.status IS NULL)")

        terminal_statuses = [v for v in statuses if v in TERMINAL_STATUSES]
        if terminal_statuses:
            self._apply_terminal_status_filter(
                terminal_statuses, conditions, params
            )

    def _apply_terminal_status_filter(
        self,
        terminal_statuses: list[CrmMemberStatus],
        conditions: list[str],
        params: dict,
    ) -> None:
        """Match members whose only memberships are terminal.

        A cancelled / ended member is one with such a membership and no
        live (active or frozen) one — so an active member who once
        cancelled an old plan is not surfaced as cancelled.

        Args:
            terminal_statuses: Cancelled / ended statuses selected.
            conditions: List of WHERE conditions to append to.
            params: Dict of query params to append to.
        """
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
