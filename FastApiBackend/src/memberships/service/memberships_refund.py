"""Refund a prior charge: Stripe call + immediate negative member_charges row.

Cash refunds skip the Stripe call; async/dashboard refunds are handled by the
refund.* webhook. Both write paths are idempotent on stripe_refund_id.
"""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

from schema.member_charge import ChargeKind, ChargeStatus
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.memberships import SQL_DIR
from src.memberships.memberships_schema import (
    MemberMembershipsRefundRequest,
    MemberMembershipsRefundResponse,
)
from src.payments.schema.payments_payment_schema import PaymentsRefundRequest
from src.payments.service.payments_stripe_payment_service import (
    PaymentsStripePaymentService,
)
from src.shared.database import DirectDatabasePool
from src.shared.gym_stripe_service import GymStripeService
from src.shared.sql_loader import load_sql
from src.stripe_webhooks.service.stripe_time import stripe_ts_to_datetime

PAYMENT_METHOD_CASH = "cash"
PAYMENT_METHOD_CARD = "card"


class MemberMembershipsRefund:
    """Issue a refund for a prior charge and record it as a negative row."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        payment_service: PaymentsStripePaymentService,
        gym_stripe_service: GymStripeService,
    ) -> None:
        self._db_pool = db_pool
        self._payments = payment_service
        self._gym_stripe = gym_stripe_service

    async def refund_charge(
        self,
        request: MemberMembershipsRefundRequest,
    ) -> MemberMembershipsRefundResponse:
        """Refund ``request.charge_id`` (full or partial).

        Raises:
            ValueError: charge not found, not refundable, or the amount exceeds
                the remaining refundable balance (the router maps these to
                404 / 400).
        """
        charge = await self._load_charge(request.member_id, request.charge_id)
        amount = self._resolve_amount(charge, request.amount)

        if charge["stripe_charge_id"]:
            return await self._refund_card(
                charge, amount, request.idempotency_key
            )
        if charge["payment_method_type"] == PAYMENT_METHOD_CASH:
            return await self._refund_cash(charge, amount)
        raise ValueError(
            "Charge is not refundable (no Stripe charge and not cash)"
        )

    async def _load_charge(
        self, member_id: UUID, charge_id: UUID
    ) -> dict:
        """Load the parent charge (gym-scoped) and validate it's refundable."""
        sql = load_sql(SQL_DIR / "member_charge_by_id.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"charge_id": str(charge_id), "member_id": str(member_id)},
            )
            row = result.mappings().fetchone()
        if row is None:
            raise ValueError("Charge not found")
        charge = dict(row)
        if (
            charge["kind"] != ChargeKind.payment
            or charge["status"] != ChargeStatus.succeeded
        ):
            raise ValueError("Only a succeeded payment can be refunded")
        return charge

    @staticmethod
    def _resolve_amount(charge: dict, requested: int | None) -> int:
        """Clamp/validate the requested refund against the remaining balance."""
        refundable = charge["amount"] - charge["already_refunded"]
        if refundable <= 0:
            raise ValueError("Charge has already been fully refunded")
        if requested is None:
            return refundable
        if requested <= 0:
            raise ValueError("Refund amount must be positive")
        if requested > refundable:
            raise ValueError(
                f"Refund amount exceeds the {refundable} refundable balance"
            )
        return requested

    async def _refund_card(
        self, charge: dict, amount: int, idempotency_key: str
    ) -> MemberMembershipsRefundResponse:
        """Refund a card charge: lock + recheck, THEN Stripe, THEN record — all
        in ONE transaction.

        The FOR-UPDATE lock + refundable recheck run BEFORE the Stripe call, so
        two concurrent card refunds serialize: the second blocks on the row lock,
        then its recheck sees ``refundable <= 0`` and raises ``ValueError``
        BEFORE any second Stripe refund is issued — the member can never be
        refunded twice. Holding the pooled connection across the Stripe call is
        the accepted tradeoff for that guarantee (a rare staff op; mirrors how
        plans ``set_price`` holds its lock across its Stripe call).
        """
        account_id = await self._gym_stripe.get_stripe_account_id(
            charge["gym_id"]
        )
        async with self._db_pool.session() as session:
            await self._assert_refundable_under_lock(
                session, charge_id=charge["charge_id"], amount=amount
            )
            refund = await self._payments.refund_payment(
                PaymentsRefundRequest(
                    stripe_charge_id=charge["stripe_charge_id"],
                    amount=amount,
                    idempotency_key=idempotency_key,
                ),
                account_id,
            )
            # Pending (non-succeeded) refunds are recorded later by the refund.*
            # webhook: no row inserted, the commit just releases the lock.
            refund_charge_id: UUID | None = None
            if refund.status == ChargeStatus.succeeded:
                refund_charge_id = await self._insert_refund_row(
                    session,
                    self._build_refund_params(
                        charge,
                        amount=refund.amount,
                        stripe_refund_id=refund.stripe_refund_id,
                        payment_method_type=charge["payment_method_type"],
                        card_last_four=charge["card_last_four"],
                        charge_time=stripe_ts_to_datetime(refund.created),
                    ),
                )
            await session.commit()
        return MemberMembershipsRefundResponse(
            refund_charge_id=refund_charge_id,
            refunded_amount=refund.amount,
            payment_method=PAYMENT_METHOD_CARD,
            status=self._safe_charge_status(refund.status),
        )

    @staticmethod
    def _safe_charge_status(stripe_status: str) -> ChargeStatus:
        """Map Stripe refund status; unrecognized values fall back to pending."""
        try:
            return ChargeStatus(stripe_status)
        except ValueError:
            return ChargeStatus.pending

    async def _refund_cash(
        self, charge: dict, amount: int
    ) -> MemberMembershipsRefundResponse:
        """Record a cash refund — recordkeeping only, no Stripe call."""
        refund_charge_id = await self._record_refund(
            charge,
            amount=amount,
            stripe_refund_id=None,
            payment_method_type=PAYMENT_METHOD_CASH,
            card_last_four=None,
            charge_time=datetime.now(UTC),
        )
        return MemberMembershipsRefundResponse(
            refund_charge_id=refund_charge_id,
            refunded_amount=amount,
            payment_method=PAYMENT_METHOD_CASH,
            status=ChargeStatus.succeeded,
        )

    async def _record_refund(
        self,
        charge: dict,
        *,
        amount: int,
        stripe_refund_id: str | None,
        payment_method_type: str | None,
        card_last_four: str | None,
        charge_time: datetime | None,
    ) -> UUID | None:
        """Insert the negative refund row under the charge-row lock; return its
        PK (None on conflict).

        The CASH path: no Stripe call, so the lock fully serializes concurrent
        cash refunds right here (``_assert_refundable_under_lock`` rechecks the
        balance under FOR UPDATE before the insert). The card path instead locks
        + rechecks BEFORE its Stripe call (see ``_refund_card``).
        """
        params = self._build_refund_params(
            charge,
            amount=amount,
            stripe_refund_id=stripe_refund_id,
            payment_method_type=payment_method_type,
            card_last_four=card_last_four,
            charge_time=charge_time,
        )
        async with self._db_pool.session() as session:
            await self._assert_refundable_under_lock(
                session, charge_id=charge["charge_id"], amount=amount
            )
            refund_charge_id = await self._insert_refund_row(session, params)
            await session.commit()
        return refund_charge_id

    @staticmethod
    def _build_refund_params(
        charge: dict,
        *,
        amount: int,
        stripe_refund_id: str | None,
        payment_method_type: str | None,
        card_last_four: str | None,
        charge_time: datetime | None,
    ) -> dict:
        """Build the negative ``member_charges`` insert params for a refund row.

        ``paid_by_member_id`` carries the payer (the parent charge's payer who
        was charged), matching how the webhook records a refund.
        """
        return {
            "invoice_id": str(charge["invoice_id"]),
            "gym_id": str(charge["gym_id"]),
            "paid_by_member_id": str(charge["charge_paid_by_member_id"]),
            "kind": ChargeKind.refund.value,
            "status": ChargeStatus.succeeded.value,
            "amount": -amount,
            "currency": charge["currency"],
            "payment_method_type": payment_method_type,
            "card_last_four": card_last_four,
            "stripe_refund_id": stripe_refund_id,
            "refunds_charge_id": str(charge["charge_id"]),
            "charge_time": charge_time,
        }

    @staticmethod
    async def _insert_refund_row(
        session: AsyncSession, params: dict
    ) -> UUID | None:
        """Execute the negative-refund INSERT in an ALREADY-OPEN session.

        Does NOT commit — the CALLER owns the transaction (card: lock + Stripe +
        this insert in one txn; cash: under ``_record_refund``'s lock). Returns
        the new row's PK, or None on ``ON CONFLICT`` (idempotent re-record).
        """
        sql = load_sql(SQL_DIR / "member_refund_insert.sql")
        result = await session.execute(text(sql), params)
        row = result.mappings().fetchone()
        return row["charge_id"] if row else None

    async def _assert_refundable_under_lock(
        self,
        session: AsyncSession,
        *,
        charge_id: UUID,
        amount: int,
    ) -> None:
        """SELECT … FOR UPDATE the charge row, then re-check refundable balance.

        Serializes concurrent cash refunds (no UNIQUE stripe_refund_id to guard them).
        Raises ValueError if the charge is gone, fully refunded, or amount exceeds balance.
        """
        lock_sql = load_sql(SQL_DIR / "member_charge_lock.sql")
        refunded_sql = load_sql(SQL_DIR / "member_charge_refunded_total.sql")
        params = {"charge_id": str(charge_id)}
        lock_result = await session.execute(text(lock_sql), params)
        lock_row = lock_result.mappings().fetchone()
        if lock_row is None:
            raise ValueError("Charge not found")
        refunded_result = await session.execute(text(refunded_sql), params)
        refunded_row = refunded_result.mappings().fetchone()
        refundable = lock_row["amount"] - refunded_row["already_refunded"]
        if refundable <= 0:
            raise ValueError("Charge has already been fully refunded")
        if amount > refundable:
            raise ValueError(
                f"Refund amount exceeds the {refundable} refundable balance"
            )
