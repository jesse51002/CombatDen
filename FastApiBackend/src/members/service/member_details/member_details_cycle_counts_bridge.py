"""Bridges member details to the class cycle counts service."""

from uuid import UUID

from src.classes.schema.classes_cycle_counts_schema import (
    ClassesCycleCountsRequest,
    MembershipUsage,
)
from src.classes.service.classes_cycle_counts_service import (
    ClassesCycleCountsService,
)


class MemberDetailsCycleCountsBridge:
    """Fetches cycle-based class usage and provides plan-level lookups.

    Args:
        cycle_counts_service: Injected cycle counts service.
    """

    def __init__(
        self,
        cycle_counts_service: ClassesCycleCountsService,
    ) -> None:
        self._service = cycle_counts_service

    async def fetch_usage(
        self,
        gym_id: UUID,
        crm_user_ids: list[UUID],
    ) -> dict[tuple[UUID, UUID], MembershipUsage]:
        """Fetch cycle counts and return a (crm_user_id, plan_id) lookup.

        Args:
            gym_id: The gym to query.
            crm_user_ids: Members to include.

        Returns:
            Dict keyed by (crm_user_id, plan_id) to MembershipUsage.
        """
        request = ClassesCycleCountsRequest(
            gym_id=gym_id,
            crm_user_ids=crm_user_ids,
        )
        response = await self._service.get_cycle_counts(request)

        lookup: dict[tuple[UUID, UUID], MembershipUsage] = {}
        for user in response.users:
            for membership in user.memberships:
                lookup[(user.crm_user_id, membership.plan_id)] = membership

        return lookup
