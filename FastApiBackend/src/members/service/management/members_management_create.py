"""Create a new gym member."""

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
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class MembersManagementCreate(MembersManagementBase):
    """Create a new gym member, optionally with a Stripe customer."""

    async def create_member(
        self,
        request: MembersManagementCreateRequest,
    ) -> MembersManagementResponse:
        """Create a new gym member, optionally with a Stripe customer.

        If payment_method_id is provided, a Stripe customer is created
        first. Stripe is called before the DB insert so a failure
        leaves no partial DB row.

        Args:
            request: Member creation data with optional card info.

        Returns:
            The created member with Stripe/card fields if applicable.

        Raises:
            ValueError: If the gym has no Stripe account and card
                info was provided.
        """
        stripe_customer_id = None
        stripe_payment_method_id = None
        card_brand = None
        card_last_four = None
        card_exp_month = None
        card_exp_year = None

        if request.payment_method_id:
            stripe_account_id = await self._get_gym_stripe_account_id(
                request.gym_id,
            )
            stripe_req = self._build_stripe_create_request(
                name=f"{request.first_name} {request.last_name}",
                email=request.email,
                phone=request.phone,
                payment_method_id=request.payment_method_id,
            )
            stripe_resp = await self._payments.create_customer(
                stripe_req,
                stripe_account_id,
            )

            stripe_customer_id = stripe_resp.stripe_customer_id
            stripe_payment_method_id = stripe_resp.stripe_payment_method_id
            card_brand = stripe_resp.card_brand
            card_last_four = stripe_resp.card_last_four
            card_exp_month = stripe_resp.card_exp_month
            card_exp_year = stripe_resp.card_exp_year

        insert_sql = load_sql(SQL_DIR / "management" / "members_management_insert.sql")
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
            "stripe_customer_id": stripe_customer_id,
            "stripe_payment_method_id": stripe_payment_method_id,
            "card_brand": card_brand,
            "card_last_four": card_last_four,
            "card_exp_month": card_exp_month,
            "card_exp_year": card_exp_year,
        }

        async with self._db_pool.session() as session:
            result = await session.execute(text(insert_sql), params)
            row = result.mappings().one()
            await session.commit()

        return MembersManagementResponse(**row)
