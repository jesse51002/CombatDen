"""Orchestrator service for the gyms domain.

Handles:
    * create_gym   — DB-first insert + Stripe Connect Express account
    * list_gyms_for_user / update_gym — basic CRUD
    * get_onboarding_status / get_fresh_onboarding_link — Stripe status
"""

import logging
from uuid import UUID

from schema.gym_employee import ThemeMode
from schema.immutable_columns import GYMS as GYMS_IMMUTABLE
from sqlalchemy import text

from src.gyms import SQL_DIR
from src.gyms.schema.gyms_schema import (
    EmployeeThemeResponse,
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
from src.gyms.service.gyms_stripe_connect_service import GymsStripeConnectService
from src.shared.column_guard import validate_mutable_columns
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql
from src.waivers.service.waivers.waivers_service import WaiversService

logger = logging.getLogger(__name__)


class GymsService:
    """Orchestrates all gym routes.

    A ``GymsStripeConnectService`` is always injected (via
    ``DependencyInjector.gyms_stripe_connect_service``); every gym is
    created with a Stripe Connect Express account.

    Args:
        db_pool: Injected database connection pool.
        stripe_connect_service: Injected Stripe Connect wrapper.
        waivers_service: Injected waivers service; used to seed-copy the
            gym's default authorized-payer waiver on creation.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        stripe_connect_service: GymsStripeConnectService,
        waivers_service: WaiversService,
    ) -> None:
        self._db_pool = db_pool
        self._waivers_service = waivers_service
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
        user_email: str,
    ) -> GymCreateResponse:
        """Create a gym and begin Stripe Express onboarding.

        A user may own multiple gyms, so this does not pre-check for
        an existing gym. Delegates to ``GymsCreateService`` for the
        DB-first insert + Stripe account + AccountLink flow.

        Raises:
            ValueError: If ``user_email`` is empty.
        """
        if not user_email:
            raise ValueError("user_email is required for Stripe onboarding")

        response = await self._create_service.create_gym(
            request=request,
            user_id=user_id,
            user_email=user_email,
        )

        # Seed-copy the gym's undeletable default authorized-payer waiver. The
        # gym is already permanent here (past the Stripe-attach cleanup window),
        # so a failure leaves a usable gym lacking only its default waiver — it
        # is logged + surfaced for an operator to re-create rather than silently
        # dropped (the authorized-payer gate needs this document to exist).
        try:
            await self._waivers_service.create_default_waiver(response.gym_id)
        except Exception:
            logger.error(
                "Failed to create the default authorized-payer waiver for "
                "gym %s (the gym is otherwise created)",
                response.gym_id,
                exc_info=True,
            )
            raise

        return response

    # ── Onboarding status ──────────────────────────────────────

    async def get_onboarding_status(
        self,
        gym_id: UUID,
    ) -> GymOnboardingStatusResponse:
        """Fetch + refresh a gym's onboarding status.

        The caller's ownership of ``gym_id`` is verified at the
        router layer before this runs.
        """
        return await self._onboarding_service.refresh(gym_id)

    async def get_fresh_onboarding_link(
        self,
        gym_id: UUID,
    ) -> GymOnboardingLinkResponse:
        """Mint a new AccountLink without re-reading the account.

        The caller's ownership of ``gym_id`` is verified at the
        router layer before this runs.
        """
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

    async def update_employee_theme(
        self,
        gym_id: UUID,
        user_id: UUID,
        theme_preference: ThemeMode,
    ) -> EmployeeThemeResponse:
        """Save the caller's CRM theme preference for one gym.

        The caller's employment at ``gym_id`` is verified at the
        router layer; the WHERE clause scopes the write to the
        caller's own ``gym_employees`` row.
        """
        sql = load_sql(SQL_DIR / "update_employee_theme.sql")
        params = {
            "theme_preference": theme_preference.value,
            "user_id": str(user_id),
            "gym_id": str(gym_id),
        }
        row = await self._db_pool.execute_with_retry(sql, params)

        if not row:
            raise ValueError("Employee not found for this gym")

        return EmployeeThemeResponse(**row)
