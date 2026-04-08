"""Service for creating, updating, and managing gym members."""

from uuid import UUID

from schema.immutable_columns import USER_GYM_PROFILES
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.member_memberships.service.member_memberships_service import (
    MemberMembershipsService,
)
from src.members import SQL_DIR
from src.members.schema.members_management_schema import (
    MembersManagementCreateRequest,
    MembersManagementResponse,
    MembersManagementUpdateCardRequest,
    MembersManagementUpdateRequest,
)
from src.payments.payments_exceptions import PaymentsResourceNotFoundError
from src.payments.schema.payments_enums import StripeResourceType
from src.payments.schema.payments_invoice_schema import (
    PaymentsInvoiceResponse,
)
from src.payments.schema.payments_members_schema import (
    PaymentsCustomerCreateRequest,
    PaymentsCustomerResponse,
    PaymentsCustomerUpdateRequest,
)
from src.payments.service.payments_stripe_members_service import (
    PaymentsStripeMembersService,
)
from src.shared.column_guard import validate_mutable_columns
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql


class MembersManagementService:
    """Orchestrates member CRUD with optional Stripe operations.

    Card operations write to the database AND delegate to
    PaymentsStripeMembersService for Stripe-side updates.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        payments_members_service: PaymentsStripeMembersService,
        member_memberships_service: MemberMembershipsService,
    ) -> None:
        self._db_pool = db_pool
        self._payments = payments_members_service
        self._memberships = member_memberships_service

    # ── helpers ──────────────────────────────────────────────────

    async def _get_stripe_info(
        self,
        crm_user_id: UUID,
    ) -> dict:
        """Fetch member's Stripe IDs and gym's stripe_account_id.

        Args:
            crm_user_id: The member's CRM user ID.

        Returns:
            Row dict with stripe_customer_id, stripe_account_id, etc.

        Raises:
            ValueError: If the member does not exist.
        """
        sql = load_sql(SQL_DIR / "management" / "members_management_get_stripe_info.sql")

        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"crm_user_id": str(crm_user_id)},
            )
            row = result.mappings().fetchone()

        if not row:
            raise ValueError(f"Member {crm_user_id} not found")
        return dict(row)

    async def _get_gym_stripe_account_id(
        self,
        gym_id: UUID,
    ) -> str:
        """Look up a gym's Stripe Connect account ID.

        Args:
            gym_id: The gym to look up.

        Returns:
            The gym's stripe_account_id.

        Raises:
            ValueError: If the gym has no Stripe account configured.
        """
        sql = load_sql(SQL_DIR / "management" / "members_management_get_gym_stripe.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"gym_id": str(gym_id)},
            )
            row = result.mappings().fetchone()

        if not row or not row["stripe_account_id"]:
            raise ValueError(f"Gym {gym_id} has no Stripe account configured")
        return row["stripe_account_id"]

    async def _get_member(
        self,
        crm_user_id: UUID,
    ) -> MembersManagementResponse:
        """Fetch a member's current data as a response model.

        Args:
            crm_user_id: The member to fetch.

        Returns:
            MembersManagementResponse with current data.

        Raises:
            ValueError: If the member does not exist.
        """
        sql = load_sql(SQL_DIR / "management" / "members_management_get_member.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"crm_user_id": str(crm_user_id)},
            )
            row = result.mappings().fetchone()

        if not row:
            raise ValueError(f"Member {crm_user_id} not found")
        return MembersManagementResponse(**row)

    def _build_stripe_create_request(
        self,
        name: str,
        email: str | None,
        phone: str | None,
        payment_method_id: str,
    ) -> PaymentsCustomerCreateRequest:
        """Build a Stripe customer create request from member data."""
        return PaymentsCustomerCreateRequest(
            name=name,
            email=email,
            phone=phone,
            payment_method_id=payment_method_id,
        )

    # ── create ───────────────────────────────────────────────────

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

    # ── update (personal info) ───────────────────────────────────

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

    # ── update card ──────────────────────────────────────────────

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

    # ── unlink payment ────────────────────────────────────────────

    async def unlink_payment(
        self,
        crm_user_id: UUID,
    ) -> MembersManagementResponse:
        """Remove a member's payment card and cancel recurring memberships.

        Clears card/payment-method fields on user_gym_profiles (keeps
        stripe_customer_id) and cancels all active recurring
        memberships at their next_due_date (or today if past/NULL).

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

        active_sql = load_sql(
            SQL_DIR / "management" / "members_management_active_recurring.sql",
        )
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(active_sql),
                {"crm_user_id": str(crm_user_id)},
            )
            memberships = result.mappings().fetchall()

        for m in memberships:
            await self._memberships.cancel(
                crm_user_id,
                UUID(str(m["gym_id"])),
                UUID(str(m["plan_id"])),
            )

        return MembersManagementResponse(**row)

    # ── list invoices ────────────────────────────────────────────

    async def list_invoices(
        self,
        crm_user_id: UUID,
        limit: int = 100,
        starting_after: str | None = None,
    ) -> list[PaymentsInvoiceResponse]:
        """List Stripe invoices for a member.

        Args:
            crm_user_id: The member whose invoices to list.
            limit: Max invoices to return (1-100).
            starting_after: Cursor for pagination (invoice ID).

        Returns:
            List of invoice details from Stripe.

        Raises:
            ValueError: If the member has no Stripe customer
                (no card on file).
        """
        info = await self._get_stripe_info(crm_user_id)

        if not info["stripe_customer_id"]:
            raise ValueError(f"Member {crm_user_id} has no Stripe customer")

        if not info["stripe_account_id"]:
            raise ValueError(f"Gym {info['gym_id']} has no Stripe account configured")

        return await self._payments.list_invoices(
            stripe_customer_id=info["stripe_customer_id"],
            stripe_account_id=info["stripe_account_id"],
            limit=limit,
            starting_after=starting_after,
        )
