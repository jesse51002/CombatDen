"""Refresh + return the Stripe onboarding status for a gym."""

import logging
from uuid import UUID

from sqlalchemy import text

from src.gyms import SQL_DIR
from src.gyms.schema.gyms_schema import (
    GymOnboardingLinkResponse,
    GymOnboardingStatusResponse,
)
from src.gyms.service.gyms_status_mapping import (
    GYM_STATUS_PENDING,
    map_account_to_snapshot,
)
from src.gyms.service.payments_stripe_connect_service import (
    PaymentsStripeConnectService,
)
from src.payments.payments_exceptions import PaymentsResourceNotFoundError
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class GymOnboardingStatusService:
    """Read + refresh a gym's Stripe onboarding status.

    Two entry points:

        * ``refresh(user_id)``: looks up the caller's owner row,
          retrieves the Stripe account, updates the DB if the
          derived status changed, and returns a status response —
          including a fresh AccountLink when the status is still
          ``pending``.

        * ``new_link(user_id)``: cheap "give me a new hosted URL"
          path for resume flow, without touching Stripe Account
          retrieve. Only valid while status is ``pending``.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        stripe_connect_service: PaymentsStripeConnectService,
    ) -> None:
        self._db_pool = db_pool
        self._stripe_connect = stripe_connect_service

    async def refresh(self, user_id: UUID) -> GymOnboardingStatusResponse:
        """Refresh the status for the caller's gym.

        Args:
            user_id: The authenticated user's Supabase ``sub``.

        Returns:
            Current status snapshot + a fresh onboarding URL if
            still pending.

        Raises:
            ValueError: If the caller does not own any gym, or the
                row has no Stripe account id (not in onboarding).
            PaymentsResourceNotFoundError: If the Stripe account
                no longer exists (linkage has been cleared).
            PaymentsStripeError: On other Stripe failures.
        """
        gym = await self._lookup_owned_gym(user_id)
        if gym is None:
            raise ValueError("No gym found for this user")

        gym_id: UUID = gym["gym_id"]
        stripe_account_id: str | None = gym["stripe_account_id"]
        current_status: str = gym["stripe_onboarding_status"]

        if not stripe_account_id:
            raise ValueError("Gym has no Stripe account — recreate via POST /api/v1/gyms/")

        try:
            account = await self._stripe_connect.retrieve_account(stripe_account_id)
        except PaymentsResourceNotFoundError:
            # Read-side 404: clear the stale CRM linkage per the
            # CLAUDE.md rule, then re-raise so the router returns
            # 404 and the Flutter app can recreate the gym.
            await self._clear_stripe_account_id(gym_id)
            raise

        snapshot = map_account_to_snapshot(account)

        if snapshot.status != current_status:
            await self._set_status(gym_id, snapshot.status)

        onboarding_url: str | None = None
        expires_at = None
        if snapshot.status == GYM_STATUS_PENDING:
            onboarding_url, expires_at = await self._stripe_connect.create_account_link(
                stripe_account_id,
            )

        return GymOnboardingStatusResponse(
            gym_id=gym_id,
            stripe_onboarding_status=snapshot.status,
            onboarding_url=onboarding_url,
            onboarding_url_expires_at=expires_at,
            details_submitted=snapshot.details_submitted,
            charges_enabled=snapshot.charges_enabled,
            payouts_enabled=snapshot.payouts_enabled,
            disabled_reason=snapshot.disabled_reason,
            requirements_currently_due=snapshot.requirements_currently_due,
        )

    async def new_link(self, user_id: UUID) -> GymOnboardingLinkResponse:
        """Mint a fresh AccountLink without re-reading the account.

        Only allowed while status is ``pending`` — the client is
        expected to route ``complete``/``disabled`` gyms elsewhere.

        Raises:
            ValueError: If the caller has no gym or the gym is not
                in a pending state.
        """
        gym = await self._lookup_owned_gym(user_id)
        if gym is None:
            raise ValueError("No gym found for this user")

        stripe_account_id: str | None = gym["stripe_account_id"]
        current_status: str = gym["stripe_onboarding_status"]

        if not stripe_account_id:
            raise ValueError("Gym has no Stripe account — recreate via POST /api/v1/gyms/")
        if current_status != GYM_STATUS_PENDING:
            raise ValueError(
                f"Cannot mint onboarding link: gym status is '{current_status}'",
            )

        url, expires_at = await self._stripe_connect.create_account_link(
            stripe_account_id,
        )
        return GymOnboardingLinkResponse(
            gym_id=gym["gym_id"],
            onboarding_url=url,
            onboarding_url_expires_at=expires_at,
        )

    # ── Private ────────────────────────────────────────────────

    async def _lookup_owned_gym(self, user_id: UUID) -> dict | None:
        """Read the caller's owned gym from the filtered ``gyms`` view.

        Uses the filtered view (not ``gyms_unfiltered``) so that a
        row whose Stripe linkage has been cleared on a read-side 404
        is invisible here — the caller will get ``None`` and the
        router will return 404, prompting the client to recreate
        via ``POST /api/v1/gyms/``.
        """
        sql = load_sql(SQL_DIR / "gyms_get_owned_by_user.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"user_id": str(user_id)},
            )
            row = result.mappings().fetchone()
        return dict(row) if row else None

    async def _set_status(self, gym_id: UUID, status_value: str) -> None:
        """UPDATE gyms_unfiltered.stripe_onboarding_status (with retry)."""
        sql = load_sql(SQL_DIR / "gyms_set_onboarding_status.sql")
        await self._db_pool.execute_with_retry(
            sql,
            {
                "gym_id": str(gym_id),
                "status": status_value,
            },
        )

    async def _clear_stripe_account_id(self, gym_id: UUID) -> None:
        """Wipe the stripe account linkage on read-side 404."""
        sql = load_sql(SQL_DIR / "gyms_clear_stripe_account_id.sql")
        try:
            await self._db_pool.execute_with_retry(
                sql,
                {"gym_id": str(gym_id)},
            )
        except Exception:
            logger.error(
                "Failed to clear stripe linkage for gym_id=%s after Stripe 404",
                gym_id,
                exc_info=True,
            )
