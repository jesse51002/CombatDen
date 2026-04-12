"""Update member personal info, payment card, and unlink payment."""

from __future__ import annotations

import logging
from uuid import UUID

from schema.immutable_columns import USER_GYM_PROFILES
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.members import SQL_DIR
from src.members.schema.members_management_schema import (
    MembersManagementResponse,
    MembersManagementUpdateCardRequest,
    MembersManagementUpdateRequest,
)
from src.members.service.management.members_management_base import (
    MembersManagementBase,
)
from src.payments.payments_exceptions import PaymentsResourceNotFoundError
from src.payments.schema.payments_enums import StripeResourceType
from src.payments.schema.payments_members_schema import (
    PaymentsCustomerResponse,
    PaymentsCustomerUpdateRequest,
)
from src.shared.column_guard import validate_mutable_columns
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class MembersManagementUpdate(MembersManagementBase):
    """Update member personal info, payment card, and unlink payment."""

    # ── Update Personal Info ───────────────────────────────────

    async def update_member(
        self,
        crm_user_id: UUID,
        request: MembersManagementUpdateRequest,
    ) -> MembersManagementResponse:
        """Update a member's personal information.

        Only non-None fields are written. Raises if any requested
        columns are immutable. If no fields are provided, returns
        the current member data unchanged.

        Card/Stripe fields are not touched — use update_card
        for that.

        Args:
            crm_user_id: The member to update.
            request: Fields to update (all optional).

        Returns:
            The updated (or current) member.

        Raises:
            ValueError: If any requested columns are immutable
                or the member is not found.
        """
        changes: dict[str, object] = {}
        for field in MembersManagementUpdateRequest.model_fields:
            value = getattr(request, field)
            if value is not None:
                if field == "account_linked_to_id":
                    changes[field] = str(value)
                else:
                    changes[field] = value

        if not changes:
            return await self._get_member(crm_user_id)

        validate_mutable_columns(USER_GYM_PROFILES, set(changes.keys()))

        set_clause = ", ".join(f"{col} = :{col}" for col in changes)
        update_sql = load_sql(
            SQL_DIR / "management" / "members_management_update.sql",
            variables={"set_clause": set_clause},
        )
        changes["crm_user_id"] = str(crm_user_id)

        async with self._db_pool.session() as session:
            result = await session.execute(text(update_sql), changes)
            row = result.mappings().fetchone()
            if not row:
                raise ValueError(f"Member {crm_user_id} not found")
            await session.commit()

        return MembersManagementResponse(**row)

    # ── Update Card ────────────────────────────────────────────

    async def update_card(
        self,
        crm_user_id: UUID,
        request: MembersManagementUpdateCardRequest,
    ) -> MembersManagementResponse:
        """Update a member's payment card in DB and Stripe.

        If the member has no Stripe customer yet, one is created.
        If they already have one, the payment method is swapped.

        Args:
            crm_user_id: The member to update.
            request: The new payment method ID.

        Returns:
            The updated member with new card details.

        Raises:
            ValueError: If member not found or gym has no Stripe
                account.
        """
        info = await self._get_stripe_info(crm_user_id)
        stripe_account_id = info["stripe_account_id"]

        if not stripe_account_id:
            raise ValueError(f"Gym {info['gym_id']} has no Stripe account configured")

        name = f"{info['first_name']} {info['last_name']}"
        email = info["email"]
        phone = info["phone"]
        create_req = self._build_stripe_create_request(
            name=name,
            email=email,
            phone=phone,
            payment_method_id=request.payment_method_id,
        )

        stripe_resp: PaymentsCustomerResponse
        if info["stripe_customer_id"]:
            try:
                stripe_resp = await self._payments.update_customer(
                    PaymentsCustomerUpdateRequest(
                        stripe_customer_id=info["stripe_customer_id"],
                        name=name,
                        email=email,
                        phone=phone,
                        payment_method_id=request.payment_method_id,
                    ),
                    stripe_account_id,
                )
            except PaymentsResourceNotFoundError as exc:
                if (
                    exc.resource_type == StripeResourceType.customer
                    and exc.resource_id == info["stripe_customer_id"]
                ):
                    stripe_resp = await self._payments.create_customer(
                        create_req,
                        stripe_account_id,
                    )
                else:
                    raise
        else:
            stripe_resp = await self._payments.create_customer(
                create_req,
                stripe_account_id,
            )

        update_card_sql = load_sql(
            SQL_DIR / "management" / "members_management_update_card.sql",
        )
        params = {
            "crm_user_id": str(crm_user_id),
            "stripe_customer_id": stripe_resp.stripe_customer_id,
            "stripe_payment_method_id": stripe_resp.stripe_payment_method_id,
            "card_brand": stripe_resp.card_brand,
            "card_last_four": stripe_resp.card_last_four,
            "card_exp_month": stripe_resp.card_exp_month,
            "card_exp_year": stripe_resp.card_exp_year,
        }

        async with self._db_pool.session() as session:
            result = await session.execute(text(update_card_sql), params)
            row = result.mappings().one()
            await session.commit()

        return MembersManagementResponse(**row)

    # ── Unlink Payment ─────────────────────────────────────────

    async def unlink_payment(
        self,
        crm_user_id: UUID,
    ) -> MembersManagementResponse:
        """Remove a member's payment card.

        Clears card/payment-method fields on user_gym_profiles (keeps
        stripe_customer_id).

        Detaches the payment method from Stripe (gracefully handles
        the case where the customer is already deleted), then clears
        card fields in the CRM.

        Args:
            crm_user_id: The member to unlink payment for.

        Returns:
            The updated member with NULLed card fields.

        Raises:
            ValueError: If the member does not exist or gym has
                no Stripe account.
        """
        info = await self._get_stripe_info(crm_user_id)

        if info["stripe_customer_id"] and info["stripe_account_id"]:
            await self._payments.unlink_customer_card(
                info["stripe_customer_id"],
                info["stripe_account_id"],
            )

        unlink_sql = load_sql(
            SQL_DIR / "management" / "members_management_unlink_payment.sql",
        )

        async with self._db_pool.session() as session:
            result = await session.execute(
                text(unlink_sql),
                {"crm_user_id": str(crm_user_id)},
            )
            row = result.mappings().fetchone()
            if not row:
                raise ValueError(f"Member {crm_user_id} not found")
            await session.commit()

        return MembersManagementResponse(**row)
