"""DB-first create flow for a gym + Stripe Express onboarding."""

import logging
from uuid import UUID

from sqlalchemy import text

from src.gyms import SQL_DIR
from src.gyms.schema.gyms_schema import GymCreateRequest, GymCreateResponse
from src.gyms.service.gyms_status_mapping import GYM_STATUS_PENDING
from src.gyms.service.payments_stripe_connect_service import (
    PaymentsStripeConnectService,
)
from src.payments.payments_exceptions import (
    PaymentsStripeError,
    StripeOrphanError,
)
from src.payments.schema.payments_enums import StripeResourceType
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class GymsCreateService:
    """Canonical DB-first create flow for a gym.

    Pattern (identical to ``membership_plans_create``):
        1. INSERT gyms_unfiltered (stripe_account_id = NULL) and
           the bootstrap gym_employees 'owner' row, in a single
           transaction. The gym row is invisible through the
           filtered ``gyms`` view at this point.
        2. Create the Stripe Express Connect account. On failure,
           delete both pending rows and re-raise.
        3. UPDATE gyms_unfiltered to set stripe_account_id and
           flip stripe_onboarding_status to 'pending'. Uses
           ``execute_with_retry`` — if all retries are exhausted,
           raise ``StripeOrphanError`` so the orphaned Stripe
           account is logged prominently.
        4. Create the AccountLink for the hosted onboarding URL.
           On failure, do NOT delete the gym row — the Stripe
           account is already bound and the client will retry via
           ``POST /me/onboarding/link``.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        stripe_connect_service: PaymentsStripeConnectService,
    ) -> None:
        self._db_pool = db_pool
        self._stripe_connect = stripe_connect_service

    async def create_gym(
        self,
        request: GymCreateRequest,
        user_id: UUID,
        user_email: str,
    ) -> GymCreateResponse:
        """Create a gym and begin Stripe Express onboarding.

        Args:
            request: Gym + owner display names.
            user_id: The authenticated user's Supabase ``sub`` UUID.
            user_email: The authenticated user's email; pre-fills
                the Stripe hosted onboarding flow.

        Returns:
            The gym id, new Stripe account id, ``pending`` status,
            and a fresh short-lived onboarding URL.

        Raises:
            PaymentsStripeError: If any Stripe call fails.
            StripeOrphanError: If the post-Stripe UPDATE fails
                after retries — an operator must reconcile.
        """
        gym_id = await self._insert_pending_rows(request, user_id, user_email)

        try:
            stripe_account_id = await self._stripe_connect.create_express_account(
                gym_id=gym_id,
                owner_email=user_email,
            )
        except Exception:
            await self._cleanup_pending(gym_id)
            raise

        await self._attach_stripe_account_id(gym_id, stripe_account_id)

        try:
            url, expires_at = await self._stripe_connect.create_account_link(
                stripe_account_id,
            )
        except PaymentsStripeError:
            # The Stripe account already exists and is bound to the
            # gym row. Do not delete the gym — the client will retry
            # the link via POST /me/onboarding/link.
            logger.error(
                "AccountLink create failed after Stripe account %s was bound to gym %s",
                stripe_account_id,
                gym_id,
                exc_info=True,
            )
            raise

        return GymCreateResponse(
            gym_id=gym_id,
            stripe_account_id=stripe_account_id,
            stripe_onboarding_status=GYM_STATUS_PENDING,
            onboarding_url=url,
            onboarding_url_expires_at=expires_at,
        )

    # ── Private ────────────────────────────────────────────────

    async def _insert_pending_rows(
        self,
        request: GymCreateRequest,
        user_id: UUID,
        user_email: str,
    ) -> UUID:
        """Insert the pending gym and owner rows in one transaction."""
        gym_sql = load_sql(SQL_DIR / "gyms_insert_pending.sql")
        owner_sql = load_sql(SQL_DIR / "gym_employees_insert_owner.sql")

        async with self._db_pool.session() as session:
            gym_result = await session.execute(
                text(gym_sql),
                {"gym_name": request.gym_name},
            )
            gym_row = dict(gym_result.mappings().one())
            gym_id: UUID = gym_row["gym_id"]

            await session.execute(
                text(owner_sql),
                {
                    "user_id": str(user_id),
                    "gym_id": str(gym_id),
                    "first_name": request.owner_first_name,
                    "last_name": request.owner_last_name,
                    "email": user_email,
                },
            )
            await session.commit()

        return gym_id

    async def _attach_stripe_account_id(
        self,
        gym_id: UUID,
        stripe_account_id: str,
    ) -> None:
        """UPDATE the pending row with the Stripe account id.

        Retries 3x with exponential backoff via
        ``execute_with_retry``. On exhaustion, raises
        ``StripeOrphanError`` so the orphaned Stripe account is
        logged with its resource id for manual reconciliation.
        """
        sql = load_sql(SQL_DIR / "gyms_set_stripe_account_id.sql")
        try:
            await self._db_pool.execute_with_retry(
                sql,
                {
                    "gym_id": str(gym_id),
                    "stripe_account_id": stripe_account_id,
                },
            )
        except Exception as exc:
            raise StripeOrphanError(
                stripe_resource_type=StripeResourceType.account,
                stripe_id=stripe_account_id,
                crm_pk=str(gym_id),
            ) from exc

    async def _cleanup_pending(self, gym_id: UUID) -> None:
        """Delete the pending owner + gym rows after a Stripe failure.

        Order matters: the gym_employees row references
        gyms_unfiltered, so the employee must go first. Both
        deletes are guarded (owner by employee_type='owner',
        gym by stripe_account_id IS NULL) so a concurrent update
        cannot accidentally remove a now-linked row.
        """
        owner_sql = load_sql(SQL_DIR / "gym_employees_delete_owner.sql")
        gym_sql = load_sql(SQL_DIR / "gyms_delete_pending.sql")

        try:
            async with self._db_pool.session() as session:
                await session.execute(
                    text(owner_sql),
                    {"gym_id": str(gym_id)},
                )
                await session.execute(
                    text(gym_sql),
                    {"gym_id": str(gym_id)},
                )
                await session.commit()
        except Exception:
            logger.error(
                "Failed to clean up pending rows for gym_id=%s "
                "after Stripe account create failure",
                gym_id,
                exc_info=True,
            )
