"""Orchestrator service for the CRM members list endpoint.

Delegates to view-specific child services and assembles
the final response.
"""

from src.members.schema.members_crm_members_list_schema import (
    CrmMembersListRequest,
    CrmMembersListResponse,
    MembersListView,
)
from src.members.service.crm_member_services.members_crm_all_service import (
    CrmAllViewService,
)
from src.members.service.crm_member_services.members_crm_base_service import (
    CrmBaseViewService,
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

    Routes each request to the view service named by
    ``request.view`` and applies ``request.filters`` as-is.
    The view (which decides the row shape) and the filters
    are independent: the service does no view/filter
    reconciliation, so a filter the user set stays put when
    the view tab changes and never moves the view.

    Args:
        db_pool: Injected database connection pool.
        dormancy_days: How long without activity makes a short-plan
            member dormant (``settings.member_dormancy_days``), passed
            down to every view service so the dormant badge and the
            dormant filter share one window.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        dormancy_days: int,
    ) -> None:
        self._db_pool = db_pool
        self._all = CrmAllViewService(db_pool, dormancy_days)
        self._trial = CrmTrialViewService(db_pool, dormancy_days)
        self._frozen = CrmFrozenViewService(db_pool, dormancy_days)
        self._overdue = CrmOverdueViewService(db_pool, dormancy_days)

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
        service = self._service_for(request.view)

        async with self._db_pool.session() as session:
            data = await service.fetch(
                session,
                request.gym_id,
                request.filters,
                request.start_index,
                request.count,
            )

        return CrmMembersListResponse(
            view=request.view,
            filters=request.filters,
            data=data,
        )

    def _service_for(
        self,
        view: MembersListView,
    ) -> CrmBaseViewService:
        """Pick the view service for the requested view.

        Args:
            view: The view the user is requesting.

        Returns:
            The matching view-specific service.
        """
        match view:
            case MembersListView.all:
                return self._all
            case MembersListView.trial:
                return self._trial
            case MembersListView.frozen:
                return self._frozen
            case MembersListView.overdue:
                return self._overdue
