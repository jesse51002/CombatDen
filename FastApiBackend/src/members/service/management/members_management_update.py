"""Update member payment card and unlink payment operations."""

from __future__ import annotations

import logging
from uuid import UUID

from schema.immutable_columns import MEMBERS as MEMBERS_IMMUTABLE
from sqlalchemy import exc as sa_exc
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.members import SQL_DIR
from src.members.schema.members_billing_schema import (
    MembersBillingProfileResponse,
    MembersBillingUpdateCardRequest,
)
from src.members.schema.members_schema import (
    MemberResponse,
    MemberUpdateData,
)
from src.members.service.management.members_management_base import (
    MembersManagementBase,
)
from src.payments.schema.metadata.stripe_customer_metadata import (
    StripeCustomerMetadata,
)
from src.payments.schema.payments_members_schema import (
    PaymentsCustomerUpdateRequest,
)
from src.shared.column_guard import validate_mutable_columns
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)

_MANAGEMENT_SQL = SQL_DIR / "management"


class MembersManagementUpdate(MembersManagementBase):
    """Update member identity, payment card, and unlink payment operations."""

    # ── Update Member (identity / contact) ─────────────────────

    async def update_member(
        self,
        member_id: UUID,
        data: MemberUpdateData,
    ) -> MemberResponse:
        """Update mutable identity / contact fields on a member row.

        Pure DB write — identity edits never touch the Stripe customer.

        Raises:
            ValueError: If no fields are provided or the member is not found.
        """
        update_fields = data.model_dump(exclude_unset=True)
        if not update_fields:
            raise ValueError("No fields provided to update")

        validate_mutable_columns(MEMBERS_IMMUTABLE, set(update_fields.keys()))

        normalized: dict[str, object] = {}
        for key, value in update_fields.items():
            if isinstance(value, UUID):
                normalized[key] = str(value)
            else:
                normalized[key] = value

        set_clause = ", ".join(f"{col} = :{col}" for col in normalized)
        sql = load_sql(SQL_DIR / "update_member.sql", {"set_clause": set_clause})
        params = {**normalized, "member_id": str(member_id)}
        row = await self._db_pool.execute_with_retry(sql, params)
        if not row:
            raise ValueError("Member not found")
        return MemberResponse(**row)

    # ── Points ─────────────────────────────────────────────────

    async def adjust_points(
        self,
        member_id: UUID,
        amount: int,
    ) -> int:
        """Apply a signed points adjustment and return the new balance.

        The SQL locks the member row (FOR UPDATE) and applies the delta only
        when the result would not go below zero. An empty RETURNING means
        either the member does not exist or the adjustment would underflow —
        both raise ValueError so the router maps them to 400.

        Args:
            member_id: The member whose balance to adjust.
            amount: Signed integer — positive awards points, negative corrects.

        Returns:
            The new points_balance after the adjustment.

        Raises:
            ValueError: Member not found, or adjustment would make balance
                negative, or a database constraint prevented the write.
        """
        sql = load_sql(SQL_DIR / "adjust_points.sql")
        try:
            async with self._db_pool.session() as session:
                result = await session.execute(
                    text(sql),
                    {"member_id": str(member_id), "amount": amount},
                )
                row = result.mappings().fetchone()
                await session.commit()
        except sa_exc.IntegrityError as exc:
            raise ValueError(
                f"Points adjustment rejected by database constraint: {exc}"
            ) from exc
        if not row:
            raise ValueError(
                f"Points adjustment rejected: member {member_id} not found "
                "or adjustment would make balance negative"
            )
        return row["points_balance"]

    # ── Update Card ────────────────────────────────────────────

    async def update_card(
        self,
        member_id: UUID,
        request: MembersBillingUpdateCardRequest,
    ) -> MembersBillingProfileResponse:
        """Swap a member's payment card in DB and Stripe.

        The member's Stripe customer always exists (provisioned at creation),
        so the payment method is attached to it. A customer is never created
        here — that lives solely in MembersManagementCreate.

        Args:
            member_id: The member to update.
            request: The new payment method ID.

        Returns:
            The updated billing profile with new card details.

        Raises:
            ValueError: If the member is not found, the gym has no Stripe
                account, or the member has no Stripe customer.
        """
        info = await self._get_stripe_info(member_id)
        stripe_account_id = info["stripe_account_id"]

        if not stripe_account_id:
            raise ValueError(f"Gym {info['gym_id']} has no Stripe account configured")

        # Every member is provisioned a Stripe customer at creation
        # (MembersManagementCreate). update_card never creates one — a missing
        # customer means a broken invariant, so we error out rather than
        # silently provisioning. create_customer has exactly one call site.
        if not info["stripe_customer_id"]:
            raise ValueError(f"Member {member_id} has no Stripe customer")

        name = f"{info['first_name']} {info['last_name']}"
        email = info["email"]
        phone = info["phone"]

        stripe_resp = await self._payments.update_customer(
            PaymentsCustomerUpdateRequest(
                stripe_customer_id=info["stripe_customer_id"],
                name=name,
                email=email,
                phone=phone,
                payment_method_id=request.payment_method_id,
                metadata=StripeCustomerMetadata(
                    member_id=member_id,
                    gym_id=info["gym_id"],
                ),
            ),
            stripe_account_id,
        )

        update_card_sql = load_sql(
            _MANAGEMENT_SQL / "members_management_update_card.sql",
        )
        params = {
            "member_id": str(member_id),
            "stripe_customer_id": stripe_resp.stripe_customer_id,
            "stripe_payment_method_id": stripe_resp.stripe_payment_method_id,
            "card_brand": stripe_resp.card_brand,
            "card_last_four": stripe_resp.card_last_four,
            "card_exp_month": stripe_resp.card_exp_month,
            "card_exp_year": stripe_resp.card_exp_year,
        }

        async with self._db_pool.session() as session:
            result = await session.execute(text(update_card_sql), params)
            result.mappings().one()  # assert exactly one row updated
            await session.commit()

        return await self._get_member(member_id)

    # ── Unlink Payment ─────────────────────────────────────────

    async def unlink_payment(
        self,
        member_id: UUID,
    ) -> MembersBillingProfileResponse:
        """Remove a member's payment card.

        Clears card/payment-method fields on members
        (keeps stripe_customer_id). Detaches the payment method from Stripe
        (gracefully handles the case where the customer is already deleted).

        Args:
            member_id: The member to unlink payment for.

        Returns:
            The updated billing profile with NULLed card fields.

        Raises:
            ValueError: If the member does not exist or gym has
                no Stripe account.
        """
        info = await self._get_stripe_info(member_id)

        if info["stripe_customer_id"] and info["stripe_account_id"]:
            await self._payments.unlink_customer_card(
                info["stripe_customer_id"],
                info["stripe_account_id"],
            )

        unlink_sql = load_sql(
            _MANAGEMENT_SQL / "members_management_unlink_payment.sql",
        )

        async with self._db_pool.session() as session:
            result = await session.execute(
                text(unlink_sql),
                {"member_id": str(member_id)},
            )
            row = result.mappings().fetchone()
            if not row:
                raise ValueError(f"Member {member_id} not found")
            await session.commit()

        return await self._get_member(member_id)
