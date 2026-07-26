"""Atomic member creation — every member is provisioned a Stripe customer.

This module owns the **single** place a Stripe customer is ever created in the
backend (``self._payments.create_customer``). ``POST /members`` routes here.

Invariants enforced:

* If the gym has no Stripe Connect account, the create is rejected up front and
  **no member row is written** (block-strict).
* If the Stripe customer create fails after the shell row is inserted, the
  pending row is deleted so a member is **never** persisted without a customer.
* A payment method is optional: when ``request.payment_method_id`` is set it is
  attached as the customer's default at creation; otherwise a cardless customer
  is created.
"""

from __future__ import annotations

import logging
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import text

# db_schema_path registers Database/python_data on sys.path; it MUST run
# before `from schema.*` (isort: skip keeps that order).
import src.shared.db_schema_path  # noqa: F401  # isort: skip
from schema.email import EmailKind  # isort: skip

from src.emails.schema.emails_schema import (
    InviteOutcome,
    MemberAppInviteEmail,
)
from src.emails.service.emails_service import EmailsService
from src.members import SQL_DIR
from src.members.schema.members_schema import (
    DuplicateMemberConflict,
    DuplicateMemberMatch,
    MemberCreateRequest,
    MemberCreateResult,
    MemberResponse,
)
from src.members.service.management.members_management_base import (
    MembersManagementBase,
)
from src.payments.schema.metadata.stripe_customer_metadata import (
    StripeCustomerMetadata,
)
from src.payments.schema.payments_members_schema import (
    PaymentsCustomerCreateRequest,
    PaymentsCustomerResponse,
)
from src.payments.service.payments_stripe_members_service import (
    PaymentsStripeMembersService,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)

_MANAGEMENT_SQL = SQL_DIR / "management"


class MembersManagementCreate(MembersManagementBase):
    """Create a member and provision its Stripe customer atomically."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        payments_members_service: PaymentsStripeMembersService,
        emails_service: EmailsService,
    ) -> None:
        super().__init__(db_pool, payments_members_service)
        self._emails = emails_service

    async def create_member(
        self,
        request: MemberCreateRequest,
    ) -> MemberCreateResult:
        """Insert the member shell, create its Stripe customer, write it back.

        Args:
            request: Identity + contact fields, plus an optional
                ``payment_method_id`` to attach as the default card.

        Returns:
            The member's billing profile, with ``stripe_customer_id`` set.

        Raises:
            ValueError: If the gym has no Stripe Connect account configured.
            HTTPException: 409 when a same-identity member already exists at the
                gym and ``allow_duplicate`` is not set (nothing is written).
        """
        # 0. Duplicate gate — BEFORE anything is written. When the request has
        #    an email and the caller has not opted to allow duplicates, reject
        #    a same-identity member (same gym + name + email) with a 409 that
        #    carries the candidate rows so the client can confirm or cancel.
        await self._check_duplicate(request)

        # 1. Block-strict: the gym MUST have a Stripe Connect account before any
        #    row is written, so we never strand a member without a customer.
        stripe_account_id = await self._get_gym_stripe_account_id(request.gym_id)

        # 2. Insert the member shell.
        member = await self._insert_shell(request)

        # 3. Create the Stripe customer — the ONLY create_customer call site.
        #    On any failure, delete the pending shell row and re-raise so a
        #    member is never persisted without a customer.
        try:
            create_req = self._build_stripe_create_request(
                name=f"{member.first_name} {member.last_name}",
                email=member.email,
                phone=member.phone,
                payment_method_id=request.payment_method_id,
                member_id=member.member_id,
                gym_id=member.gym_id,
            )

            stripe_resp = await self._payments.create_customer(
                create_req,
                stripe_account_id,
            )
        except Exception:
            await self._delete_pending(member.member_id)
            raise

        # 4. Persist the Stripe customer (+ card details if a PM was attached).
        await self._write_stripe_customer(member.member_id, stripe_resp)

        created = await self._get_member(member.member_id)
        if not request.send_invite:
            return MemberCreateResult(
                member=created,
                invite=InviteOutcome.not_requested,
            )
        # 5. Claim the app invite — LAST, and only once the member is fully
        #    created (row + Stripe customer). Everything above can still
        #    unwind and delete the shell row; an invite claimed before that
        #    could outlive a member who was never created. A mail failure
        #    from here on is recorded on the email_log row and retried by the
        #    reconciler, and never fails this create.
        email_id, outcome = await self._emails.request_send(
            MemberAppInviteEmail(
                kind=EmailKind.member_app_invite,
                gym_id=request.gym_id,
                member_id=member.member_id,
            )
        )
        return MemberCreateResult(
            member=created,
            invite=outcome,
            email_id=email_id,
        )

    # ── Helpers ────────────────────────────────────────────────

    async def _check_duplicate(self, request: MemberCreateRequest) -> None:
        """Reject a same-identity duplicate create with a 409 (nothing written).

        A no-op when ``request.email`` is None (no reliable identity to dedupe
        on) or ``request.allow_duplicate`` is True (the caller confirmed).
        Otherwise, on ≥1 same-gym match by name + email, raise ``HTTPException``
        409 whose ``detail`` carries the candidate rows.
        """
        if request.email is None or request.allow_duplicate:
            return

        matches = await self._find_duplicates(request)
        if not matches:
            return

        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=DuplicateMemberConflict(matches=matches).model_dump(),
        )

    async def _find_duplicates(
        self,
        request: MemberCreateRequest,
    ) -> list[DuplicateMemberMatch]:
        """Return same-identity members at the gym (name + email, normalized)."""
        sql = load_sql(SQL_DIR / "find_members_by_identity.sql")
        params = {
            "gym_id": str(request.gym_id),
            "first_name": request.first_name,
            "last_name": request.last_name,
            "email": request.email,
        }
        async with self._db_pool.session() as session:
            result = await session.execute(text(sql), params)
            rows = result.mappings().all()

        return [
            DuplicateMemberMatch(
                member_id=str(row["member_id"]),
                first_name=row["first_name"],
                last_name=row["last_name"],
                email=row["email"],
                photo_url=row["photo_url"],
            )
            for row in rows
        ]

    async def _insert_shell(self, request: MemberCreateRequest) -> MemberResponse:
        """Insert the member identity + contact row (no Stripe columns yet)."""
        params = {
            "gym_id": str(request.gym_id),
            "first_name": request.first_name,
            "last_name": request.last_name,
            "email": request.email,
            "current_rank_id": (str(request.current_rank_id) if request.current_rank_id else None),
            "phone": request.phone,
            "address": request.address,
            "date_of_birth": request.date_of_birth,
            "emergency_contact_name": request.emergency_contact_name,
            "emergency_contact_phone": request.emergency_contact_phone,
            "emergency_contact_email": request.emergency_contact_email,
            "photo_url": request.photo_url,
        }
        sql = load_sql(SQL_DIR / "insert_member.sql")
        row = await self._db_pool.execute_with_retry(sql, params)
        if not row:
            raise RuntimeError("INSERT did not return a row")
        return MemberResponse(**row)

    def _build_stripe_create_request(
        self,
        name: str,
        email: str | None,
        phone: str | None,
        payment_method_id: str | None,
        *,
        member_id: UUID,
        gym_id: UUID,
    ) -> PaymentsCustomerCreateRequest:
        """Build a Stripe customer create request from member data.

        ``payment_method_id`` is optional: ``None`` builds a cardless customer
        create. Used only by MembersManagementCreate (the sole create_customer
        call site).
        """
        return PaymentsCustomerCreateRequest(
            name=name,
            email=email,
            phone=phone,
            payment_method_id=payment_method_id,
            metadata=StripeCustomerMetadata(
                member_id=member_id,
                gym_id=gym_id,
            ),
        )

    async def _write_stripe_customer(
        self,
        member_id: UUID,
        stripe_resp: PaymentsCustomerResponse,
    ) -> None:
        """Write the new Stripe customer + card details onto the member row."""
        sql = load_sql(
            _MANAGEMENT_SQL / "members_management_set_stripe_customer.sql",
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
            result = await session.execute(text(sql), params)
            result.mappings().one()  # assert exactly one row updated
            await session.commit()

    async def _delete_pending(self, member_id: UUID) -> None:
        """Remove a pending shell row whose Stripe customer never materialised."""
        sql = load_sql(
            _MANAGEMENT_SQL / "members_management_delete_pending.sql",
        )
        async with self._db_pool.session() as session:
            await session.execute(text(sql), {"member_id": str(member_id)})
            await session.commit()
