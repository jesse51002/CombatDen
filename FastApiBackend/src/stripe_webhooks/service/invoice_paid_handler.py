"""Handler for Stripe ``invoice.paid`` events."""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING, Any
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.shared.gym_timezone import get_gym_timezone, stripe_ts_to_gym_date
from src.shared.paying_member_lock import LockBusyError
from src.shared.sql_loader import load_sql
from src.stripe_webhooks import SQL_DIR
from src.stripe_webhooks.service.stripe_json import dump_stripe_payload
from src.stripe_webhooks.service.stripe_time import (
    stripe_ts_to_datetime,
)
from src.stripe_webhooks.stripe_webhooks_exceptions import (
    SubscriptionItemPendingError,
)

if TYPE_CHECKING:
    from src.member_memberships.service.payment_sync.payment_sync_service import (
        PaymentSyncService,
    )
    from src.shared.paying_member_lock import PayingMemberLock

logger = logging.getLogger(__name__)

EVENT_TYPE = "invoice.paid"
CHARGE_KIND_PAYMENT = "payment"
CHARGE_STATUS_SUCCEEDED = "succeeded"
INVOICE_STATUS_PAID = "paid"
PAYMENT_METHOD_TYPE_CASH = "cash"
LINE_ITEM_TYPE_MEMBERSHIP = "membership"
LINE_ITEM_TYPE_CUSTOM = "custom"
# Fallback label when a Stripe line carries no description (name <> '').
LINE_ITEM_DEFAULT_NAME = "Charge"

# Stripe serializes bool metadata values as string "true" / "false".
STRIPE_METADATA_TRUE = "true"


class InvoicePaidHandler:
    """Apply an ``invoice.paid`` event to the CRM database.

    Writes:
      - Upsert ``member_invoices`` row to ``status='paid'``.
      - Insert one ``member_invoice_line_items`` row per Stripe line
        (name / amount / quantity; membership lines carry their item_id),
        so the bill is itemized.
      - Update ``member_memberships`` for each billed subscription item
        (``last_paid_date``, ``next_due_date``).
      - Insert a ``member_charges`` row representing the successful
        payment.

    Metadata is read directly from the raw invoice envelope — the
    webhook is a pure reader at the Stripe boundary. The typed
    ``StripeSubscriptionMetadata`` / ``StripeMembershipOneTimeMetadata``
    / ``StripeAdHocInvoiceMetadata`` models guard the *write* side;
    here we only pull out a small set of flow-control fields.

    After a subscription invoice is paid it also triggers the once-discount
    settle (``PaymentSyncService.settle_once_discounts``) so a ``once`` discount
    Stripe just consumed has its ``end_date`` stamped promptly.
    """

    def __init__(
        self,
        payment_sync_service: PaymentSyncService,
        paying_lock: PayingMemberLock,
    ) -> None:
        self._sync = payment_sync_service
        self._paying_lock = paying_lock

    async def handle(
        self,
        session: AsyncSession,
        event: dict[str, Any],
        gym_id: UUID,
    ) -> None:
        invoice = event["data"]["object"]
        stripe_invoice_id = invoice.get("id")
        if not stripe_invoice_id:
            raise ValueError("invoice.paid event is missing invoice id")

        raw_metadata = invoice.get("metadata") or {}
        is_one_time = raw_metadata.get("crm_one_time_payment") == STRIPE_METADATA_TRUE
        paid_with_cash = raw_metadata.get("crm_paid_with_cash") == STRIPE_METADATA_TRUE

        member_id = await self._resolve_member_id(
            session,
            invoice,
            gym_id,
            raw_metadata=raw_metadata,
            is_one_time=is_one_time,
        )
        if member_id is None:
            subscription_item_ids = [
                line["subscription_item"]
                for line in self._lines(invoice)
                if line.get("subscription_item")
            ]
            if subscription_item_ids:
                raise SubscriptionItemPendingError(
                    stripe_invoice_id=stripe_invoice_id,
                    gym_id=str(gym_id),
                    subscription_item_ids=subscription_item_ids,
                )
            return

        invoice_row = await self._upsert_invoice(
            session,
            invoice,
            gym_id,
            member_id,
        )
        invoice_id: UUID = invoice_row["invoice_id"]

        await self._insert_line_items(session, invoice, gym_id, invoice_id)

        if not is_one_time:
            await self._update_memberships(session, invoice, gym_id)
            await self._settle_once_discounts(member_id, gym_id)
        await self._insert_payment_charge(
            session,
            invoice,
            gym_id,
            member_id,
            invoice_id,
            paid_with_cash=paid_with_cash,
        )

    # ── Helpers ────────────────────────────────────────────────

    async def _resolve_member_id(
        self,
        session: AsyncSession,
        invoice: dict[str, Any],
        gym_id: UUID,
        *,
        raw_metadata: dict[str, str],
        is_one_time: bool,
    ) -> UUID | None:
        """Find a member_id for this invoice.

        One-time invoices carry ``member_id`` directly in metadata
        (they have no subscription item to look up). Subscription
        invoices are resolved by matching any line's
        ``subscription_item`` against ``member_memberships``.
        """
        if is_one_time:
            member_id_str = raw_metadata.get("member_id")
            if not member_id_str:
                raise ValueError(
                    "invoice.paid one-time invoice is missing member_id "
                    f"in metadata (stripe_invoice_id={invoice.get('id')})"
                )
            return UUID(member_id_str)

        membership_sql = load_sql(SQL_DIR / "membership_by_stripe_item.sql")
        for line in self._lines(invoice):
            stripe_item_id = line.get("subscription_item")
            if not stripe_item_id:
                continue
            result = await session.execute(
                text(membership_sql),
                {
                    "stripe_item_id": stripe_item_id,
                    "gym_id": str(gym_id),
                },
            )
            row = result.mappings().fetchone()
            if row is not None:
                return row["member_id"]
        return None

    async def _upsert_invoice(
        self,
        session: AsyncSession,
        invoice: dict[str, Any],
        gym_id: UUID,
        member_id: UUID,
    ) -> dict[str, Any]:
        upsert_sql = load_sql(SQL_DIR / "member_invoice_upsert.sql")
        paid_at_ts = invoice.get("status_transitions", {}).get("paid_at") or invoice.get("created")
        params = {
            "gym_id": str(gym_id),
            "member_id": str(member_id),
            "status": INVOICE_STATUS_PAID,
            "total_amount": int(invoice.get("amount_paid") or invoice.get("total") or 0),
            "currency": invoice.get("currency", "usd"),
            "stripe_invoice_id": invoice["id"],
            "stripe_payment_intent_id": invoice.get("payment_intent"),
            "invoice_time": stripe_ts_to_datetime(paid_at_ts),
            "stripe_event_payload": dump_stripe_payload(invoice),
        }
        result = await session.execute(text(upsert_sql), params)
        row = result.mappings().fetchone()
        if row is None:
            raise RuntimeError(f"Failed to upsert invoice for stripe_invoice_id={invoice['id']}")
        return dict(row)

    async def _insert_line_items(
        self,
        session: AsyncSession,
        invoice: dict[str, Any],
        gym_id: UUID,
        invoice_id: UUID,
    ) -> None:
        """Persist each Stripe invoice line so the bill is itemized.

        A line that maps to a membership (its ``subscription_item``
        resolves to a ``member_memberships`` row) is stored as
        ``item_type='membership'`` with that ``item_id``; everything
        else is ``custom``. Idempotent on the Stripe line id. Negative
        lines (proration credits) are skipped — the schema requires
        ``amount >= 0``.
        """
        membership_sql = load_sql(SQL_DIR / "membership_by_stripe_item.sql")
        insert_sql = load_sql(SQL_DIR / "member_invoice_line_item_insert.sql")

        for line in self._lines(invoice):
            line_item_id = line.get("id")
            if not line_item_id:
                continue
            amount = int(line.get("amount") or 0)
            if amount < 0:
                continue

            item_type = LINE_ITEM_TYPE_CUSTOM
            item_id: str | None = None
            stripe_item_id = line.get("subscription_item")
            if stripe_item_id:
                result = await session.execute(
                    text(membership_sql),
                    {
                        "stripe_item_id": stripe_item_id,
                        "gym_id": str(gym_id),
                    },
                )
                row = result.mappings().fetchone()
                if row is not None:
                    item_type = LINE_ITEM_TYPE_MEMBERSHIP
                    item_id = str(row["item_id"])

            await session.execute(
                text(insert_sql),
                {
                    "line_item_id": line_item_id,
                    "invoice_id": str(invoice_id),
                    "gym_id": str(gym_id),
                    "item_type": item_type,
                    "name": (line.get("description") or "").strip()
                    or LINE_ITEM_DEFAULT_NAME,
                    "amount": amount,
                    "quantity": max(1, int(line.get("quantity") or 1)),
                    "stripe_product_id": self._line_product(line),
                    "item_id": item_id,
                },
            )

    @staticmethod
    def _line_product(line: dict[str, Any]) -> str | None:
        """Best-effort Stripe product id across invoice-line shapes."""
        price = line.get("price")
        if isinstance(price, dict):
            product = price.get("product")
            if isinstance(product, dict):
                return product.get("id")
            if isinstance(product, str):
                return product
        pricing = line.get("pricing") or {}
        details = pricing.get("price_details") or {}
        return details.get("product")

    async def _update_memberships(
        self,
        session: AsyncSession,
        invoice: dict[str, Any],
        gym_id: UUID,
    ) -> None:
        membership_sql = load_sql(SQL_DIR / "membership_by_stripe_item.sql")
        update_sql = load_sql(SQL_DIR / "member_memberships_update_payment_dates.sql")
        gym_timezone = await get_gym_timezone(session, gym_id)
        paid_at_ts = invoice.get("status_transitions", {}).get("paid_at") or invoice.get("created")
        last_paid_date = (
            stripe_ts_to_gym_date(paid_at_ts, gym_timezone)
            if paid_at_ts
            else None
        )

        for line in self._lines(invoice):
            stripe_item_id = line.get("subscription_item")
            if not stripe_item_id:
                continue

            result = await session.execute(
                text(membership_sql),
                {
                    "stripe_item_id": stripe_item_id,
                    "gym_id": str(gym_id),
                },
            )
            row = result.mappings().fetchone()
            if row is None:
                logger.warning(
                    "invoice.paid: no membership for stripe_item_id=%s gym_id=%s",
                    stripe_item_id,
                    gym_id,
                )
                continue

            period_end_ts = line.get("period", {}).get("end")
            next_due_date = (
                stripe_ts_to_gym_date(period_end_ts, gym_timezone)
                if period_end_ts
                else None
            )

            await session.execute(
                text(update_sql),
                {
                    "item_id": str(row["item_id"]),
                    "gym_id": str(gym_id),
                    "last_paid_date": last_paid_date,
                    "next_due_date": next_due_date,
                },
            )

    async def _settle_once_discounts(
        self,
        member_id: UUID,
        gym_id: UUID,
    ) -> None:
        """Promptly finalize any ``once`` discount Stripe just invoiced.

        When a subscription invoice is paid, a consumed ``once`` coupon drops off
        the live sub — stamp its ``end_date`` now instead of waiting for the
        member's next manual op (or the deferred reconciler). A no-op when the
        family has no unconsumed ``once`` discounts.

        Best-effort: a failure here must NOT roll back the invoice/charge writes
        (the critical path), so it is logged and swallowed — the next sync /
        reconciler re-settles (the settle is idempotent). The settle runs in its
        own DB transaction (a separate pool), independent of this webhook's.
        """
        try:
            async with self._paying_lock.lock([member_id]):
                await self._sync.settle_once_discounts(member_id)
        except LockBusyError:
            logger.info(
                "invoice.paid once-discount settle skipped (family busy) for "
                "member_id=%s gym_id=%s; the next sync settles it",
                member_id,
                gym_id,
            )
        except Exception:
            logger.error(
                "invoice.paid once-discount settle failed for "
                "member_id=%s gym_id=%s",
                member_id,
                gym_id,
                exc_info=True,
            )

    async def _insert_payment_charge(
        self,
        session: AsyncSession,
        invoice: dict[str, Any],
        gym_id: UUID,
        member_id: UUID,
        invoice_id: UUID,
        *,
        paid_with_cash: bool,
    ) -> None:
        stripe_charge_id = invoice.get("charge")
        amount_paid = int(invoice.get("amount_paid") or 0)

        # Schema requires payment rows to have a stripe_charge_id
        # UNLESS payment_method_type='cash' (paid out of band). Skip
        # the charge insert for zero-amount paid invoices with no
        # underlying charge (e.g. 100%-off trials).
        if not stripe_charge_id and not paid_with_cash:
            if amount_paid == 0:
                return
            raise ValueError(
                f"invoice.paid has amount_paid={amount_paid} but no charge id "
                f"(stripe_invoice_id={invoice.get('id')})"
            )

        payment_method_type = PAYMENT_METHOD_TYPE_CASH if paid_with_cash else None

        insert_sql = load_sql(SQL_DIR / "member_charge_insert.sql")
        paid_at_ts = invoice.get("status_transitions", {}).get("paid_at") or invoice.get("created")
        params = {
            "invoice_id": str(invoice_id),
            "gym_id": str(gym_id),
            "member_id": str(member_id),
            "kind": CHARGE_KIND_PAYMENT,
            "status": CHARGE_STATUS_SUCCEEDED,
            "amount": amount_paid,
            "currency": invoice.get("currency", "usd"),
            "payment_method_type": payment_method_type,
            "stripe_charge_id": stripe_charge_id,
            "stripe_refund_id": None,
            "refunds_charge_id": None,
            "charge_time": stripe_ts_to_datetime(paid_at_ts),
            "stripe_event_payload": dump_stripe_payload(invoice),
        }
        await session.execute(text(insert_sql), params)

    @staticmethod
    def _lines(invoice: dict[str, Any]) -> list[dict[str, Any]]:
        lines = invoice.get("lines") or {}
        return list(lines.get("data") or [])
