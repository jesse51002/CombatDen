"""Orchestrator service for the gyms domain.

Handles:
    * create_gym   — DB-first insert + Stripe Connect Express account
    * list_gyms_for_user / update_gym — basic CRUD
    * get_onboarding_status / get_fresh_onboarding_link — Stripe status
"""

import logging
from uuid import UUID

from schema.immutable_columns import GYMS as GYMS_IMMUTABLE
from sqlalchemy import text

from src.gyms import SQL_DIR
from src.gyms.schema.gyms_schema import (
    GymCreateRequest,
    GymCreateResponse,
    GymOnboardingLinkResponse,
    GymOnboardingStatusResponse,
    GymResponse,
    GymUpdateData,
    GymWithRoleResponse,
)
from src.gyms.service.gyms_create_service import GymsCreateService
from src.gyms.service.gyms_onboarding_service import GymsOnboardingService
from src.gyms.service.gyms_status_mapping import (
    GYM_STATUS_COMPLETE,
    GYM_STATUS_NOT_STARTED,
    GYM_STATUS_PENDING,
)
from src.gyms.service.gyms_stripe_connect_service import GymsStripeConnectService
from src.shared.column_guard import validate_mutable_columns
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class GymsService:
    """Orchestrates all gym routes.

    ``stripe_connect_service`` is optional. When ``None`` (no Stripe
    configured), ``create_gym`` falls through to the legacy
    non-Stripe path and the onboarding endpoints raise ValueError.
    The integrator injects a ``GymsStripeConnectService`` instance
    via ``DependencyInjector.gyms_stripe_connect_service``.

    Args:
        db_pool: Injected database connection pool.
        stripe_connect_service: Injected Stripe Connect wrapper.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        stripe_connect_service: GymsStripeConnectService | None = None,
    ) -> None:
        self._db_pool = db_pool
        self._create_service: GymsCreateService | None = None
        self._onboarding_service: GymsOnboardingService | None = None

        if stripe_connect_service is not None:
            self._create_service = GymsCreateService(
                db_pool=db_pool,
                stripe_connect_service=stripe_connect_service,
            )
            self._onboarding_service = GymsOnboardingService(
                db_pool=db_pool,
                stripe_connect_service=stripe_connect_service,
            )

    # ── Create ─────────────────────────────────────────────────

    async def create_gym(
        self,
        request: GymCreateRequest,
        user_id: UUID,
        user_email: str | None = None,
    ) -> GymCreateResponse:
        """Create a gym and begin Stripe Express onboarding.

        A user may own multiple gyms, so this no longer pre-checks
        for an existing gym. When a ``GymsStripeConnectService`` is
        wired (normal path) it delegates to ``GymsCreateService`` for
        the DB-first insert + Stripe account + AccountLink flow.

        Raises:
            ValueError: If Stripe is wired but ``user_email`` is None.
        """
        if self._create_service is not None:
            if not user_email:
                raise ValueError("user_email is required for Stripe onboarding")

            return await self._create_service.create_gym(
                request=request,
                user_id=user_id,
                user_email=user_email,
            )

        # Legacy (no Stripe) path — kept for local dev / tests.
        return await self._create_gym_no_stripe(request, user_id)

    async def _create_gym_no_stripe(
        self,
        request: GymCreateRequest,
        user_id: UUID,
    ) -> GymCreateResponse:
        """Non-Stripe fallback for local dev / tests without Stripe creds."""
        raise NotImplementedError(
            "Stripe Connect is required. Inject GymsStripeConnectService into GymsService.",
        )

    # ── Onboarding status ──────────────────────────────────────

    async def get_onboarding_status(
        self,
        gym_id: UUID,
    ) -> GymOnboardingStatusResponse:
        """Fetch + refresh a gym's onboarding status.

        The caller's ownership of ``gym_id`` is verified at the
        router layer before this runs.

        Raises:
            ValueError: If Stripe is not configured.
        """
        if self._onboarding_service is None:
            raise ValueError("Stripe Connect is not configured")
        return await self._onboarding_service.refresh(gym_id)

    async def get_fresh_onboarding_link(
        self,
        gym_id: UUID,
    ) -> GymOnboardingLinkResponse:
        """Mint a new AccountLink without re-reading the account.

        The caller's ownership of ``gym_id`` is verified at the
        router layer before this runs.

        Raises:
            ValueError: If Stripe is not configured.
        """
        if self._onboarding_service is None:
            raise ValueError("Stripe Connect is not configured")
        return await self._onboarding_service.new_link(gym_id)

    # ── Basic CRUD ─────────────────────────────────────────────

    async def list_gyms_for_user(
        self,
        user_id: UUID,
    ) -> list[GymWithRoleResponse]:
        """Return every gym the caller may administer (owner/admin).

        Each gym is annotated with the caller's ``employee_type`` for
        it. Returns an empty list when the user administers no gyms.
        """
        async with self._db_pool.session() as session:
            rows = (
                (
                    await session.execute(
                        text(load_sql(SQL_DIR / "gyms_list_for_user.sql")),
                        {"user_id": str(user_id)},
                    )
                )
                .mappings()
                .fetchall()
            )

        return [GymWithRoleResponse(**row) for row in rows]

    async def update_gym(
        self,
        gym_id: UUID,
        data: GymUpdateData,
    ) -> GymResponse:
        """Update mutable fields on a gym row."""
        update_fields = data.model_dump(exclude_unset=True, exclude_none=True)

        if not update_fields:
            raise ValueError("No fields provided to update")

        validate_mutable_columns(GYMS_IMMUTABLE, set(update_fields.keys()))

        set_clause = ", ".join(f"{col} = :{col}" for col in update_fields)
        sql = load_sql(
            SQL_DIR / "update_gym.sql",
            {"set_clause": set_clause},
        )

        params = {**update_fields, "gym_id": str(gym_id)}
        row = await self._db_pool.execute_with_retry(sql, params)

        if not row:
            raise ValueError("Gym not found")

        return GymResponse(**row)


# Re-export status constants so the router can reference them
# without reaching across service modules.
__all__ = [
    "GYM_STATUS_COMPLETE",
    "GYM_STATUS_NOT_STARTED",
    "GYM_STATUS_PENDING",
    "GymsService",
]
