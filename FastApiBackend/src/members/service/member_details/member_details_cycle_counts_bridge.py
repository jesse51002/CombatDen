"""Bridges member details to the class cycle counts service."""

from uuid import UUID

from src.checkin.schema.cycle_counts_schema import (
    CheckinCycleCountsRequest,
    MembershipUsage,
)
from src.checkin.service.cycle_counts_service import CycleCountsService


class MemberDetailsCycleCountsBridge:
    """Fetches cycle-based class usage and provides per-membership lookups.

    Args:
        cycle_counts_service: Injected cycle counts service.
    """

    def __init__(
        self,
        cycle_counts_service: CycleCountsService,
    ) -> None:
        self._service = cycle_counts_service

    async def fetch_usage(
        self,
        gym_id: UUID,
        member_ids: list[UUID],
    ) -> dict[tuple[UUID, UUID], MembershipUsage]:
        """Fetch cycle counts and return a (member_id, item_id) lookup.

        Keyed per membership (item_id), not per plan, so a member holding two
        packs on the same plan keeps a distinct usage bucket per pack. Frozen
        / ended memberships are included — the breakdown is informational and
        should still show their usage.

        Args:
            gym_id: The gym to query.
            member_ids: Members to include.

        Returns:
            Dict keyed by (member_id, item_id) to MembershipUsage.
        """
        request = CheckinCycleCountsRequest(
            gym_id=gym_id,
            member_ids=member_ids,
        )
        response = await self._service.get_cycle_counts(request)

        lookup: dict[tuple[UUID, UUID], MembershipUsage] = {}
        for user in response.users:
            for membership in user.memberships:
                lookup[(user.member_id, membership.item_id)] = membership

        return lookup
