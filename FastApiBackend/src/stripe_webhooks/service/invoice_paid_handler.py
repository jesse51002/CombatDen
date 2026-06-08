"""Handler for Stripe ``invoice.paid`` events."""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING, Any
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.payments.service.payments_stripe_client import PaymentsStripeClient
from src.shared.gym_timezone import get_gym_timezone, stripe_ts_to_gym_date
from src.shared.paying_member_lock import LockBusyError
from src.shared.sql_loader import load_sql
from src.stripe_webhooks import SQL_DIR
from src.stripe_webhooks.service.stripe_invoice_fields import (
    invoice_metadata,
    line_subscription_item,
)
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
INVOICE_STATUS_PAID = "paid"
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

    The succeeded ``member_charges`` row is NOT written here — a paid
    invoice's payment(s) arrive on the separate ``invoice_payment.paid``
    event (one per payment, partial or full), which
    ``InvoicePaymentPaidHandler`` records. This handler owns the bill;
    that handler owns the money movement.

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
        stripe_client: PaymentsStripeClient,
    ) -> None:
        self._sync = payment_sync_service
        self._paying_lock = paying_lock
        self._stripe = stripe_client.client

    async def handle(
        self,
        session: AsyncSession,
        event: dict[str, Any],
        gym_id: UUID,
    ) -> None:
        await self.record(
            session,
            event["data"]["object"],
            gym_id,
            stripe_account_id=event.get("account"),
        )

    async def record(
        self,
        session: AsyncSession,
        invoice: dict[str, Any],
        gym_id: UUID,
        *,
        stripe_account_id: str | None = None,
    ) -> None:
        """Apply a paid invoice (object) to the CRM.

        The seam shared by the webhook dispatcher (``handle`` unwraps the event
        envelope) and the reconciler invoice fetcher (which passes the listed
        invoice object directly). Idempotent via the upsert / line-item /
        discount-audit unique constraints.
        """
        stripe_invoice_id = invoice.get("id")
        if not stripe_invoice_id:
            raise ValueError("invoice.paid event is missing invoice id")

        raw_metadata = invoice_metadata(invoice)
        is_one_time = raw_metadata.get("crm_one_time_payment") == STRIPE_METADATA_TRUE

        member_id = await self._resolve_member_id(
            session,
            invoice,
            gym_id,
            raw_metadata=raw_metadata,
            is_one_time=is_one_time,
        )
        if member_id is None:
            subscription_item_ids = [
                item_id
                for line in self._lines(invoice)
                if (item_id := line_subscription_item(line))
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

        await self._capture_discounts(
            session,
            invoice,
            gym_id,
            invoice_id,
            stripe_account_id=stripe_account_id,
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
            stripe_item_id = line_subscription_item(line)
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
            stripe_item_id = line_subscription_item(line)
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
            stripe_item_id = line_subscription_item(line)
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

    async def _capture_discounts(
        self,
        session: AsyncSession,
        invoice: dict[str, Any],
        gym_id: UUID,
        invoice_id: UUID,
        *,
        stripe_account_id: str | None,
    ) -> None:
        """Snapshot the invoice's discounts into ``member_invoice_applied_discounts``.

        The webhook payload carries discount *amounts* but only opaque ``di_``
        Discount ids — so we retrieve the invoice with the coupon expanded to map
        each ``di_`` to its Stripe coupon id, and store ``{amount_off, stripe_coupon_id}``
        per discount (no CRM-discount link — the coupon id is the identifier).

        Best-effort and isolated: a no-op when the invoice has no discounts (the
        common case → no Stripe call); otherwise the retrieve + inserts run inside
        a SAVEPOINT so any failure here rolls back ONLY the audit, never the
        invoice / line-item writes. Idempotent on re-delivery via the row's
        ``UNIQUE (invoice_id, stripe_coupon_id)``.
        """
        discount_amounts = invoice.get("total_discount_amounts") or []
        if not discount_amounts or not stripe_account_id:
            return

        try:
            coupon_by_discount = await self._fetch_invoice_coupons(
                invoice["id"], stripe_account_id
            )
            if not coupon_by_discount:
                return
            insert_sql = load_sql(
                SQL_DIR / "member_invoice_applied_discount_insert.sql"
            )
            async with session.begin_nested():
                for entry in discount_amounts:
                    discount_ref = entry.get("discount")
                    coupon_id = (
                        coupon_by_discount.get(discount_ref)
                        if isinstance(discount_ref, str)
                        else None
                    )
                    if not coupon_id:
                        continue
                    await session.execute(
                        text(insert_sql),
                        {
                            "invoice_id": str(invoice_id),
                            "gym_id": str(gym_id),
                            "amount_off": int(entry.get("amount") or 0),
                            "stripe_coupon_id": coupon_id,
                        },
                    )
        except Exception:
            logger.error(
                "invoice.paid discount-audit capture failed "
                "(stripe_invoice_id=%s gym_id=%s); invoice/charge unaffected",
                invoice.get("id"),
                gym_id,
                exc_info=True,
            )

    async def _fetch_invoice_coupons(
        self,
        stripe_invoice_id: str,
        stripe_account_id: str,
    ) -> dict[str, str]:
        """Map each invoice Discount id (``di_``) to its Stripe coupon id.

        Retrieves the invoice with its Discount objects expanded (the webhook
        payload sends only ``di_`` ids). Returns ``{}`` if nothing resolves.
        """
        opts = PaymentsStripeClient.connect_opts_readonly(stripe_account_id)
        retrieved = await self._stripe.v1.invoices.retrieve_async(
            stripe_invoice_id,
            params={"expand": ["discounts"]},
            options=opts,
        )
        coupon_by_discount: dict[str, str] = {}
        for discount in getattr(retrieved, "discounts", None) or []:
            if isinstance(discount, str):
                continue  # unexpanded id — can't resolve the coupon
            discount_id = getattr(discount, "id", None)
            coupon_id = self._discount_coupon_id(discount)
            if discount_id and coupon_id:
                coupon_by_discount[discount_id] = coupon_id
        return coupon_by_discount

    @staticmethod
    def _discount_coupon_id(discount: Any) -> str | None:
        """The coupon id off a Stripe Discount, dahlia-shaped.

        Dahlia nests it: ``discount.source = {type: 'coupon', coupon: '<id>'}``
        (``coupon`` is the id string). Falls back to the legacy
        ``discount.coupon`` (object or id string) so the capture survives an
        API-version skew either way. ``getattr(..., None)`` is safe on a
        Stripe object — a missing field returns the default, not raises.
        """
        source = getattr(discount, "source", None)
        coupon = getattr(source, "coupon", None) if source is not None else None
        if isinstance(coupon, str):
            return coupon
        coupon_id = getattr(coupon, "id", None) if coupon is not None else None
        if coupon_id:
            return coupon_id
        legacy = getattr(discount, "coupon", None)  # pre-dahlia fallback
        if isinstance(legacy, str):
            return legacy
        return getattr(legacy, "id", None) if legacy is not None else None

    @staticmethod
    def _lines(invoice: dict[str, Any]) -> list[dict[str, Any]]:
        lines = invoice.get("lines") or {}
        return list(lines.get("data") or [])
