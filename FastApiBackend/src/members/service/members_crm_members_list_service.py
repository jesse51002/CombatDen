"""Orchestrator service for the CRM members list endpoint.

Delegates to view-specific child services and assembles
the final response.
"""

from src.members.schema.members_crm_members_list_schema import (
    CrmMembersListRequest,
    CrmMembersListResponse,
    MembershipStatus,
    MembersListFilters,
    MembersListView,
)
from src.members.service.crm_member_services.members_crm_all_service import (
    CrmAllViewService,
)
from src.members.service.crm_member_services.members_crm_frozen_service import (
    CrmFrozenViewService,
)
from src.members.service.crm_member_services.members_crm_overdue_service import (
    CrmOverdueViewService,
)
from src.members.service.crm_member_services.members_crm_trial_service import (
    CrmTrialViewService,
)
from src.shared.database import DirectDatabasePool


class CrmMembersListService:
    """Orchestrator for the CRM members list screen.

    Routes requests to the appropriate view service and
    assembles the response with total counts.

    Args:
        db_pool: Injected database connection pool.
    """

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool
        self._all = CrmAllViewService(db_pool)
        self._trial = CrmTrialViewService(db_pool)
        self._frozen = CrmFrozenViewService(db_pool)
        self._overdue = CrmOverdueViewService(db_pool)

    async def get_crm_members_list(
        self,
        request: CrmMembersListRequest,
    ) -> CrmMembersListResponse:
        """Return filtered, sorted, paginated members list.

        Args:
            request: The members list request with view,
                filters, and pagination params.

        Returns:
            CrmMembersListResponse with pre-formatted rows.
        """
        resolved_view, cleaned_filters = self._reconcile_view_and_filters(
            request.prev_view,
            request.requested_view,
            request.filters,
        )

        match resolved_view:
            case MembersListView.all:
                service = self._all
            case MembersListView.trial:
                service = self._trial
            case MembersListView.frozen:
                service = self._frozen
            case MembersListView.overdue:
                service = self._overdue

        async for session in self._db_pool.session():
            data = await service.fetch(
                session,
                request.gym_id,
                cleaned_filters,
                request.start_index,
                request.count,
            )

        return CrmMembersListResponse(
            view=resolved_view,
            filters=cleaned_filters,
            data=data,
        )

    def _reconcile_view_and_filters(
        self,
        prev_view: MembersListView,
        requested_view: MembersListView,
        filters: MembersListFilters,
    ) -> tuple[MembersListView, MembersListFilters]:
        """Reconcile the requested view with the active filters.

        When the user switches views, auto-inject or strip
        status filters. When the user changes filters on the
        same view, resolve the view from the status filters.

        Args:
            prev_view: The view the user was on before.
            requested_view: The view the user is requesting.
            filters: Active filters from the frontend.

        Returns:
            Tuple of (resolved_view, cleaned_filters).
        """
        if prev_view != requested_view:
            return self._reconcile_view_switch(requested_view, filters)
        return self._reconcile_filter_change(requested_view, filters)

    def _reconcile_view_switch(
        self,
        requested_view: MembersListView,
        filters: MembersListFilters,
    ) -> tuple[MembersListView, MembersListFilters]:
        """Handle reconciliation when the user switches views.

        Replaces membership_status with the view's required
        status, keeps date_range.

        Args:
            requested_view: The view the user is switching to.
            filters: Current filters from the frontend.

        Returns:
            Tuple of (resolved_view, cleaned_filters).
        """
        match requested_view:
            case MembersListView.trial:
                status = [MembershipStatus.trial]
            case MembersListView.frozen:
                status = [MembershipStatus.frozen]
            case MembersListView.overdue:
                status = [MembershipStatus.overdue]
            case _:
                status = []

        filters.membership_status = status
        return requested_view, filters

    def _reconcile_filter_change(
        self,
        current_view: MembersListView,
        filters: MembersListFilters,
    ) -> tuple[MembersListView, MembersListFilters]:
        """Handle reconciliation when filters change on the
        same view.

        If exactly one membership status is selected, switch
        to the matching view. Otherwise resolve to All.

        Args:
            current_view: The view the user is currently on.
            filters: Updated filters from the frontend.

        Returns:
            Tuple of (resolved_view, cleaned_filters).
        """
        statuses = filters.membership_status

        if len(statuses) != 1:
            return MembersListView.all, filters

        match statuses[0]:
            case MembershipStatus.trial:
                return MembersListView.trial, filters
            case MembershipStatus.frozen:
                return MembersListView.frozen, filters
            case MembershipStatus.overdue:
                return MembersListView.overdue, filters
            case _:
                return MembersListView.all, filters
