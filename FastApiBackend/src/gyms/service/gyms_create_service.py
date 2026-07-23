"""DB-first create flow for a gym + Stripe Connect Express onboarding."""

import logging
from uuid import UUID

from schema.gym import StripeOnboardingStatus
from sqlalchemy import text

from src.gyms import SQL_DIR
from src.gyms.schema.gyms_schema import GymCreateRequest, GymCreateResponse
from src.gyms.service.gyms_stripe_connect_service import GymsStripeConnectService
from src.payments.payments_exceptions import (
    PaymentsStripeError,
    StripeOrphanError,
)
from src.payments.schema.payments_enums import StripeResourceType
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql
from src.waivers.service.waivers_service import WaiversService

logger = logging.getLogger(__name__)


class GymsCreateService:
    """Canonical DB-first create flow for a gym + Stripe onboarding.

    Pattern:
        1. INSERT into ``gyms`` (stripe_account_id = NULL, status =
           'not_started') and the bootstrap ``gym_employees`` 'owner'
           row in a single transaction.
        2. Seed the gym's default authorized-payer waiver. On failure,
           ``_cleanup_pending`` tears down the pending gym + owner +
           waiver rows — no orphaned Stripe account (none exists yet).
        3. Create the Stripe Express Connect account. On failure,
           delete the pending rows (owner, waiver, gym) and re-raise.
        4. UPDATE ``gyms`` to set ``stripe_account_id`` and flip
           ``stripe_onboarding_status`` to 'pending'. Uses
           ``execute_with_retry`` — if all retries are exhausted,
           raise ``StripeOrphanError`` so the orphaned Stripe account
           is logged prominently.
        5. Create the AccountLink for the hosted onboarding URL.
           On failure, do NOT delete the gym row — the Stripe account
           is already bound and the client will retry via
           ``POST /{gym_id}/onboarding/link``.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        stripe_connect_service: GymsStripeConnectService,
        waivers_service: WaiversService,
    ) -> None:
        self._db_pool = db_pool
        self._stripe_connect = stripe_connect_service
        self._waivers_service = waivers_service

    async def create_gym(
        self,
        request: GymCreateRequest,
        user_email: str,
    ) -> GymCreateResponse:
        """Create a gym and begin Stripe Express onboarding.

        Args:
            request: Gym + owner display names.
            user_email: The authenticated user's verified email — the
                owner ``gym_employees`` row's identity (stored lowercase)
                and the pre-fill for the Stripe hosted onboarding flow.

        Returns:
            The gym id, new Stripe account id, ``pending`` status,
            and a fresh short-lived onboarding URL.

        Raises:
            PaymentsStripeError: If any Stripe call fails.
            StripeOrphanError: If the post-Stripe UPDATE fails
                after retries — an operator must reconcile.
        """
        gym_id = await self._insert_pending_rows(request, user_email)

        # Seed the default authorized-payer waiver BEFORE creating the Stripe
        # account. If this fails, _cleanup_pending tears down the pending rows
        # cleanly — no Stripe account has been created yet, so there is nothing
        # to orphan.
        try:
            await self._waivers_service.create_payer_auth_waiver(gym_id)
        except Exception:
            await self._cleanup_pending(gym_id)
            raise

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
            # The Stripe account already exists and is bound to the gym row.
            # Do not delete the gym — the client will retry via
            # POST /{gym_id}/onboarding/link.
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
            stripe_onboarding_status=StripeOnboardingStatus.pending,
            onboarding_url=url,
            onboarding_url_expires_at=expires_at,
        )

    # ── Private ────────────────────────────────────────────────

    async def _insert_pending_rows(
        self,
        request: GymCreateRequest,
        user_email: str,
    ) -> UUID:
        """Insert the pending gym and owner rows in one transaction.

        The owner ``gym_employees`` row is keyed on the caller's verified
        email (stored lowercase — it is identity now), so it is
        lowercased before binding.
        """
        gym_sql = load_sql(SQL_DIR / "gyms_insert_pending.sql")
        owner_sql = load_sql(SQL_DIR / "insert_owner_employee.sql")

        async with self._db_pool.session() as session:
            gym_result = await session.execute(
                text(gym_sql),
                {
                    "gym_name": request.gym_name,
                    "gym_description": request.gym_description,
                    "timezone": request.timezone,
                },
            )
            gym_row = dict(gym_result.mappings().one())
            gym_id: UUID = gym_row["gym_id"]

            await session.execute(
                text(owner_sql),
                {
                    "gym_id": str(gym_id),
                    "first_name": request.owner_first_name,
                    "last_name": request.owner_last_name,
                    "phone": request.owner_phone,
                    "email": user_email.lower(),
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

        Retries with exponential backoff via ``execute_with_retry``.
        On exhaustion, raises ``StripeOrphanError`` so the orphaned
        Stripe account is logged with its resource id for manual
        reconciliation.
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
        """Delete the pending owner + default-waiver + gym rows on failure.

        Order matters:
          1. Owner employee (``gym_employees`` FK references ``gyms``).
          2. NULL out ``gym_waivers.current_version_id`` to break the
             circular FK before deleting version rows.
          3. Delete ``gym_waiver_versions`` rows for the default waiver.
          4. Delete the ``gym_waivers`` default row.
          5. Delete the pending ``gyms`` row (``stripe_account_id IS NULL``
             guard prevents removing a now-linked row).

        The circular FK between ``gym_waivers.current_version_id``
        (→ ``gym_waiver_versions``) and ``gym_waiver_versions.waiver_id``
        (→ ``gym_waivers``) is resolved by NULLing the forward pointer
        first, then deleting versions, then deleting the waiver.

        All five statements run in one transaction so a partial cleanup
        cannot leave dangling rows. The outer try/except logs and swallows
        exceptions — cleanup is best-effort; the original error is the
        caller's concern.
        """
        owner_sql = load_sql(SQL_DIR / "gym_employees_delete_owner.sql")
        null_version_sql = load_sql(
            SQL_DIR / "gyms_null_payer_auth_waiver_current_version.sql"
        )
        delete_versions_sql = load_sql(
            SQL_DIR / "gyms_delete_payer_auth_waiver_versions.sql"
        )
        delete_waiver_sql = load_sql(SQL_DIR / "gyms_delete_payer_auth_waiver.sql")
        gym_sql = load_sql(SQL_DIR / "gyms_delete_pending.sql")

        try:
            async with self._db_pool.session() as session:
                await session.execute(
                    text(owner_sql),
                    {"gym_id": str(gym_id)},
                )
                await session.execute(
                    text(null_version_sql),
                    {"gym_id": str(gym_id)},
                )
                await session.execute(
                    text(delete_versions_sql),
                    {"gym_id": str(gym_id)},
                )
                await session.execute(
                    text(delete_waiver_sql),
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
