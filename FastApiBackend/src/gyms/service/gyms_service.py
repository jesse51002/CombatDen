"""Orchestrator service for the gyms domain."""

import logging
from uuid import UUID

from sqlalchemy import text

from src.gyms import SQL_DIR
from src.gyms.schema.gyms_schema import (
    GymCreateRequest,
    GymCreateResponse,
    GymOnboardingLinkResponse,
    GymOnboardingStatusResponse,
)
from src.gyms.service.gyms_create import GymsCreateService
from src.gyms.service.gyms_onboarding_status import GymOnboardingStatusService
from src.gyms.service.gyms_status_mapping import (
    GYM_STATUS_COMPLETE,
    GYM_STATUS_DISABLED,
    GYM_STATUS_PENDING,
)
from src.gyms.service.payments_stripe_connect_service import (
    PaymentsStripeConnectService,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class GymAlreadyExistsError(Exception):
    """Raised by ``create_gym`` when the caller already owns a gym.

    Carries the existing gym's current ``stripe_onboarding_status``
    so the router can translate to the correct 409 detail message.
    """

    def __init__(self, existing_status: str) -> None:
        super().__init__(
            f"User already owns a gym (status={existing_status})",
        )
        self.existing_status = existing_status


class GymsService:
    """Orchestrates the three gym routes.

    Thin layer — most work is delegated to ``GymsCreateService``
    and ``GymOnboardingStatusService``. The only logic that lives
    here is the "user already owns a gym" pre-check used by the
    create endpoint.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        stripe_connect_service: PaymentsStripeConnectService,
    ) -> None:
        self._db_pool = db_pool
        self._create_service = GymsCreateService(
            db_pool=db_pool,
            stripe_connect_service=stripe_connect_service,
        )
        self._status_service = GymOnboardingStatusService(
            db_pool=db_pool,
            stripe_connect_service=stripe_connect_service,
        )

    async def create_gym(
        self,
        request: GymCreateRequest,
        user_id: UUID,
        user_email: str,
    ) -> GymCreateResponse:
        """Create a gym — or raise if the user already owns one.

        Raises:
            GymAlreadyExistsError: If the caller owns any gym
                (regardless of status). The router maps this to
                409 with a status-specific detail message.
        """
        existing = await self._lookup_existing_gym(user_id)
        if existing is not None:
            raise GymAlreadyExistsError(existing["stripe_onboarding_status"])

        return await self._create_service.create_gym(
            request=request,
            user_id=user_id,
            user_email=user_email,
        )

    async def get_onboarding_status(
        self,
        user_id: UUID,
    ) -> GymOnboardingStatusResponse:
        """Fetch + refresh the caller's onboarding status."""
        return await self._status_service.refresh(user_id)

    async def get_fresh_onboarding_link(
        self,
        user_id: UUID,
    ) -> GymOnboardingLinkResponse:
        """Mint a new AccountLink without re-reading the account."""
        return await self._status_service.new_link(user_id)

    # ── Private ────────────────────────────────────────────────

    async def _lookup_existing_gym(self, user_id: UUID) -> dict | None:
        """Check whether the caller already owns any gym."""
        sql = load_sql(SQL_DIR / "gyms_get_owned_by_user.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"user_id": str(user_id)},
            )
            row = result.mappings().fetchone()
        return dict(row) if row else None


# Re-export status constants so the router can reference them
# without reaching across service modules.
__all__ = [
    "GYM_STATUS_COMPLETE",
    "GYM_STATUS_DISABLED",
    "GYM_STATUS_PENDING",
    "GymAlreadyExistsError",
    "GymsService",
]
