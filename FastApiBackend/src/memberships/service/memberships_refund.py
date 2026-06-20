"""Refund a prior charge on a member's payment history.

A refund hits Stripe (for a card charge) and is recorded **immediately** as a
negative ``member_charges`` row — the endpoint writes the row itself rather than
waiting for the ``refund.*`` webhook. The webhook then only matters for the
cases the endpoint can't see synchronously: an async refund that comes back
``pending`` and succeeds later, and a refund initiated from the Stripe Dashboard.
Both write paths are idempotent on ``stripe_refund_id``.

A cash charge has no Stripe charge to reverse, so it is refunded as a
recordkeeping-only negative cash row with no Stripe call.

Sibling of the charge-card op (``memberships_charge_card.py``): both are ad-hoc
money-movement actions the CRM triggers from a member's billing history. It is a
standalone service (not part of the ``MemberMembershipsService`` facade) because
it touches no subscription state — no payment-sync, no paying-lock.
"""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import UUID

from schema.member_charge import ChargeKind, ChargeStatus
from sqlalchemy import text

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
        """Refund a card charge via Stripe and record the succeeded row."""
        account_id = await self._gym_stripe.get_stripe_account_id(
            charge["gym_id"]
        )
        refund = await self._payments.refund_payment(
            PaymentsRefundRequest(
                stripe_charge_id=charge["stripe_charge_id"],
                amount=amount,
                idempotency_key=idempotency_key,
            ),
            account_id,
        )
        # A pending async refund is recorded later by the refund.* webhook when
        # it succeeds; only a succeeded refund is written here.
        refund_charge_id: UUID | None = None
        if refund.status == ChargeStatus.succeeded:
            refund_charge_id = await self._record_refund(
                charge,
                amount=refund.amount,
                stripe_refund_id=refund.stripe_refund_id,
                payment_method_type=charge["payment_method_type"],
                card_last_four=charge["card_last_four"],
                charge_time=stripe_ts_to_datetime(refund.created),
            )
        return MemberMembershipsRefundResponse(
            refund_charge_id=refund_charge_id,
            refunded_amount=refund.amount,
            payment_method=PAYMENT_METHOD_CARD,
            status=ChargeStatus(refund.status),
        )

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
        """Insert the negative refund row; return its PK (None on conflict).

        ``member_id`` carries the parent's member (the payer who was charged),
        matching how the webhook records a refund.
        """
        sql = load_sql(SQL_DIR / "member_refund_insert.sql")
        params = {
            "invoice_id": str(charge["invoice_id"]),
            "gym_id": str(charge["gym_id"]),
            "member_id": str(charge["charge_member_id"]),
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
        async with self._db_pool.session() as session:
            result = await session.execute(text(sql), params)
            row = result.mappings().fetchone()
            await session.commit()
        return row["charge_id"] if row else None
