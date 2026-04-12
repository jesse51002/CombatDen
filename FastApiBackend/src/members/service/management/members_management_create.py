"""Create a new gym member: DB first, then Stripe customer, then set stripe ID."""

from __future__ import annotations

import logging

from sqlalchemy import text

from src.members import SQL_DIR
from src.members.schema.members_management_schema import (
    MembersManagementCreateRequest,
    MembersManagementResponse,
)
from src.members.service.management.members_management_base import (
    MembersManagementBase,
)
from src.payments.payments_exceptions import StripeOrphanError
from src.payments.schema.payments_enums import StripeResourceType
from src.payments.schema.payments_members_schema import (
    PaymentsCustomerCreateRequest,
)
from src.shared.db_first_helpers import cleanup_pending_row
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class MembersManagementCreate(MembersManagementBase):
    """Create a new gym member using the DB-first pattern."""

    async def create_member(
        self,
        request: MembersManagementCreateRequest,
    ) -> MembersManagementResponse:
        """Insert CRM row, create Stripe customer, then set stripe IDs.

        A Stripe customer is ALWAYS created (even without a payment
        method) so the profile is visible through the filtered view.

        Args:
            request: Member creation data with optional card info.

        Returns:
            The created member with Stripe/card fields.

        Raises:
            ValueError: If the gym has no Stripe account.
            StripeOrphanError: If Stripe succeeds but the DB
                update fails after retries.
        """
        stripe_account_id = await self._get_gym_stripe_account_id(
            request.gym_id,
        )

        # ── Step 1: DB insert (NULL stripe_customer_id) ──────────
        row = await self._insert_profile(request)
        crm_user_id = str(row["crm_user_id"])

        # ── Step 2: Stripe create customer (always) ──────────────
        try:
            stripe_resp = await self._payments.create_customer(
                PaymentsCustomerCreateRequest(
                    name=f"{request.first_name} {request.last_name}",
                    email=request.email,
                    phone=request.phone,
                    payment_method_id=request.payment_method_id,
                    metadata={"crm_user_id": crm_user_id},
                ),
                stripe_account_id,
            )
        except Exception:
            await cleanup_pending_row(
                delete_fn=lambda: self._delete_pending(crm_user_id),
                entity_name="user_gym_profile",
                crm_pk=crm_user_id,
            )
            raise

        # ── Step 3: Set stripe IDs ───────────────────────────────
        set_customer_sql = load_sql(
            SQL_DIR / "management" / "members_management_set_stripe_customer.sql",
        )
        try:
            await self._db_pool.execute_with_retry(
                set_customer_sql,
                {
                    "crm_user_id": crm_user_id,
                    "stripe_customer_id": stripe_resp.stripe_customer_id,
                    "stripe_payment_method_id": stripe_resp.stripe_payment_method_id,
                    "card_brand": stripe_resp.card_brand,
                    "card_last_four": stripe_resp.card_last_four,
                    "card_exp_month": stripe_resp.card_exp_month,
                    "card_exp_year": stripe_resp.card_exp_year,
                },
            )
        except Exception as exc:
            raise StripeOrphanError(
                stripe_resource_type=StripeResourceType.customer,
                stripe_id=stripe_resp.stripe_customer_id,
                crm_pk=crm_user_id,
            ) from exc

        return await self._get_member(row["crm_user_id"])

    # ── Private ────────────────────────────────────────────────

    async def _insert_profile(
        self,
        request: MembersManagementCreateRequest,
    ) -> dict:
        """Insert a profile row with NULL stripe_customer_id."""
        sql = load_sql(
            SQL_DIR / "management" / "members_management_insert.sql",
        )
        params = {
            "gym_id": str(request.gym_id),
            "first_name": request.first_name,
            "last_name": request.last_name,
            "phone": request.phone,
            "email": request.email,
            "address": request.address,
            "emergency_contact_name": request.emergency_contact_name,
            "emergency_contact_phone": request.emergency_contact_phone,
            "emergency_contact_email": request.emergency_contact_email,
            "account_linked_to_id": (
                str(request.account_linked_to_id) if request.account_linked_to_id else None
            ),
            "stripe_customer_id": None,
            "stripe_payment_method_id": None,
            "card_brand": None,
            "card_last_four": None,
            "card_exp_month": None,
            "card_exp_year": None,
        }
        async with self._db_pool.session() as session:
            result = await session.execute(text(sql), params)
            row = dict(result.mappings().one())
            await session.commit()
        return row

    async def _delete_pending(self, crm_user_id: str) -> None:
        """Hard-delete a pending profile row (NULL stripe_customer_id)."""
        sql = load_sql(
            SQL_DIR / "management" / "members_management_delete_pending.sql",
        )
        async with self._db_pool.session() as session:
            await session.execute(
                text(sql),
                {"crm_user_id": crm_user_id},
            )
            await session.commit()
