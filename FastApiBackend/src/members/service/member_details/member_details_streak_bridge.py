"""Bridges member details to the class streak service."""

from uuid import UUID

from src.classes.service.classes_streak_service import ClassesStreakService


class MemberDetailsStreakBridge:
    """Fetches the weekly attendance streak for a member.

    Args:
        streak_service: Injected streak calculation service.
    """

    def __init__(
        self,
        streak_service: ClassesStreakService,
    ) -> None:
        self._service = streak_service

    async def fetch_streak(
        self,
        gym_id: UUID,
        crm_user_id: UUID,
    ) -> int:
        """Fetch the weekly class attendance streak.

        Args:
            gym_id: The gym to query.
            crm_user_id: The member to query.

        Returns:
            Number of consecutive weeks with at least one class.
        """
        return await self._service.get_streak(crm_user_id, gym_id)
