"""Handler for Stripe ``invoice.paid`` events."""

from __future__ import annotations

import json
import logging
from typing import Any
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.core.config import settings
from src.payments.service.payments_stripe_client import PaymentsStripeClient
from src.shared.gym_timezone import get_gym_timezone, stripe_ts_to_gym_date
from src.shared.sql_loader import load_sql
from src.stripe_webhooks import SQL_DIR
from src.stripe_webhooks.service.stripe_attribution import (
    resolve_subscription_attribution,
)
from src.stripe_webhooks.service.stripe_invoice_fields import (
    invoice_metadata,
    invoice_payment_intent_id,
    line_subscription_item,
)
from src.stripe_webhooks.service.stripe_json import dump_stripe_payload
from src.stripe_webhooks.service.stripe_time import (
    stripe_ts_to_datetime,
)
from src.stripe_webhooks.stripe_webhooks_exceptions import (
    SubscriptionItemPendingError,
)

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

    Upserts the invoice row, inserts line items, updates membership dates.
    Charges are written by ``InvoicePaymentPaidHandler`` (``invoice_payment.paid``).
    """

    def __init__(
        self,
        stripe_client: PaymentsStripeClient,
    ) -> None:
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
        """Apply a paid invoice object to the CRM. Idempotent via upsert/unique constraints."""
        stripe_invoice_id = invoice.get("id")
        if not stripe_invoice_id:
            raise ValueError("invoice.paid event is missing invoice id")

        # Paginate the lines ONCE; every consumer below works the full set, so a
        # >10-line family / class-pack invoice is never silently truncated to
        # Stripe's embedded first page (line records, payment dates, discounts).
        lines = await self._all_lines(invoice, stripe_account_id)

        raw_metadata = invoice_metadata(invoice)
        is_one_time = raw_metadata.get("crm_one_time_payment") == STRIPE_METADATA_TRUE

        paid_by_member_id, paid_for = await self._resolve_attribution(
            session,
            invoice,
            lines,
            gym_id,
            raw_metadata=raw_metadata,
            is_one_time=is_one_time,
        )
        if paid_by_member_id is None:
            subscription_item_ids = [
                item_id
                for line in lines
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
            paid_by_member_id,
            paid_for,
        )
        invoice_id: UUID = invoice_row["invoice_id"]

        await self._insert_line_items(session, lines, gym_id, invoice_id)

        if not is_one_time:
            await self._update_memberships(session, invoice, lines, gym_id)

        await self._capture_discounts(
            session,
            invoice,
            lines,
            gym_id,
            invoice_id,
            stripe_account_id=stripe_account_id,
        )

    # ── Helpers ────────────────────────────────────────────────

    async def _resolve_attribution(
        self,
        session: AsyncSession,
        invoice: dict[str, Any],
        lines: list[dict[str, Any]],
        gym_id: UUID,
        *,
        raw_metadata: dict[str, str],
        is_one_time: bool,
    ) -> tuple[UUID | None, list[UUID]]:
        """Resolve ``(paid_by_member_id, paid_for)``."""
        if is_one_time:
            return self._attribution_from_metadata(raw_metadata, invoice)

        return await resolve_subscription_attribution(session, lines, gym_id)

    @staticmethod
    def _attribution_from_metadata(
        raw_metadata: dict[str, str],
        invoice: dict[str, Any],
    ) -> tuple[UUID, list[UUID]]:
        """Read paid_by_member_id + paid_for from one-time invoice metadata."""
        payer_str = (
            raw_metadata.get("paid_by_member_id")
            or raw_metadata.get("member_id")
        )
        if not payer_str:
            raise ValueError(
                "invoice.paid one-time invoice is missing "
                "paid_by_member_id/member_id in metadata "
                f"(stripe_invoice_id={invoice.get('id')})"
            )
        paid_by_member_id = UUID(payer_str)
        paid_for_raw = raw_metadata.get("paid_for")
        if paid_for_raw:
            paid_for = [UUID(m) for m in json.loads(paid_for_raw)]
        else:
            paid_for = [paid_by_member_id]
        return paid_by_member_id, paid_for

    async def _upsert_invoice(
        self,
        session: AsyncSession,
        invoice: dict[str, Any],
        gym_id: UUID,
        paid_by_member_id: UUID,
        paid_for: list[UUID],
    ) -> dict[str, Any]:
        upsert_sql = load_sql(SQL_DIR / "member_invoice_upsert.sql")
        paid_at_ts = invoice.get("status_transitions", {}).get("paid_at") or invoice.get("created")
        params = {
            "gym_id": str(gym_id),
            "paid_by_member_id": str(paid_by_member_id),
            "paid_for": json.dumps([str(m) for m in paid_for]),
            "status": INVOICE_STATUS_PAID,
            "total_amount": int(invoice.get("amount_paid") or invoice.get("total") or 0),
            "currency": invoice.get("currency", "usd"),
            "stripe_invoice_id": invoice["id"],
            "stripe_payment_intent_id": invoice_payment_intent_id(invoice),
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
        lines: list[dict[str, Any]],
        gym_id: UUID,
        invoice_id: UUID,
    ) -> None:
        """Persist each invoice line. Membership lines carry item_id; negative lines skipped."""
        membership_sql = load_sql(SQL_DIR / "memberships_by_stripe_item.sql")
        insert_sql = load_sql(SQL_DIR / "member_invoice_line_item_insert.sql")

        for line in lines:
            # Proration lines (incl. the zero-dollar edge) are not real charges.
            if self._is_proration(line):
                continue
            line_item_id = line.get("id")
            if not line_item_id:
                continue
            amount = int(line.get("amount") or 0)
            if amount < 0:
                continue

            item_type = LINE_ITEM_TYPE_CUSTOM
            item_id: str | None = None
            # Recurring: use subscription_item. One-time: stripe_item_id equals the line id.
            lookup_id = line_subscription_item(line) or line_item_id
            result = await session.execute(
                text(membership_sql),
                {
                    "stripe_item_id": lookup_id,
                    "gym_id": str(gym_id),
                },
            )
            rows = result.mappings().all()
            if rows:
                # Consolidated items have multiple co-owners; store the first as representative.
                item_type = LINE_ITEM_TYPE_MEMBERSHIP
                item_id = str(rows[0]["item_id"])

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
        lines: list[dict[str, Any]],
        gym_id: UUID,
    ) -> None:
        membership_sql = load_sql(SQL_DIR / "memberships_by_stripe_item.sql")
        update_sql = load_sql(SQL_DIR / "member_memberships_update_payment_dates.sql")
        gym_timezone = await get_gym_timezone(session, gym_id)
        paid_at_ts = invoice.get("status_transitions", {}).get("paid_at") or invoice.get("created")
        last_paid_date = (
            stripe_ts_to_gym_date(paid_at_ts, gym_timezone)
            if paid_at_ts
            else None
        )

        for line in lines:
            stripe_item_id = line_subscription_item(line)
            if not stripe_item_id:
                continue

            # Proration period.end is not the next billing date — skip it.
            if self._is_proration(line):
                continue

            result = await session.execute(
                text(membership_sql),
                {
                    "stripe_item_id": stripe_item_id,
                    "gym_id": str(gym_id),
                },
            )
            rows = result.mappings().all()
            if not rows:
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

            for row in rows:
                await session.execute(
                    text(update_sql),
                    {
                        "item_id": str(row["item_id"]),
                        "gym_id": str(gym_id),
                        "last_paid_date": last_paid_date,
                        "next_due_date": next_due_date,
                    },
                )

    async def _capture_discounts(
        self,
        session: AsyncSession,
        invoice: dict[str, Any],
        lines: list[dict[str, Any]],
        gym_id: UUID,
        invoice_id: UUID,
        *,
        stripe_account_id: str | None,
    ) -> None:
        """Write per-line discount audit rows. Best-effort: failures roll back only the audit."""
        # Gate on per-line discount_amounts, never the invoice-level
        # total_discount_amounts rollup: dahlia can omit the rollup while lines
        # still carry discounts, and an empty rollup would silently skip the audit.
        if not stripe_account_id or not any(
            (line.get("discount_amounts") or [])
            for line in lines
            if not self._is_proration(line)
        ):
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
                for line in lines:
                    if self._is_proration(line):
                        continue
                    line_item_id = line.get("id")
                    if not line_item_id:
                        continue
                    for entry in line.get("discount_amounts") or []:
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
                                "line_item_id": line_item_id,
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

    async def _all_lines(
        self,
        invoice: dict[str, Any],
        stripe_account_id: str | None,
    ) -> list[dict[str, Any]]:
        """Return EVERY invoice line as a plain dict.

        ``self._lines`` reads only Stripe's embedded first page (default 10), so
        a >10-line family / class-pack invoice would silently truncate. We keep
        the embedded page and follow ``has_more`` through the line-items endpoint
        (StripeObjects round-tripped to the webhook's dict shape). The common
        (<=10-line) case — and the case with no Stripe account to page against —
        makes no extra request.
        """
        lines = self._lines(invoice)
        line_page = invoice.get("lines") or {}
        if not line_page.get("has_more") or not stripe_account_id:
            return lines

        opts = PaymentsStripeClient.connect_opts_readonly(stripe_account_id)
        invoice_id = invoice["id"]
        starting_after: str | None = lines[-1].get("id") if lines else None
        while True:
            params: dict[str, Any] = {
                "limit": settings.invoice_line_items_page_limit
            }
            if starting_after:
                params["starting_after"] = starting_after
            page = await self._stripe.v1.invoices.line_items.list_async(
                invoice_id,
                params=params,
                options=opts,
            )
            data = [json.loads(str(obj)) for obj in page.data]
            lines.extend(data)
            if not data or not getattr(page, "has_more", False):
                break
            starting_after = data[-1].get("id")
        return lines

    async def _fetch_invoice_coupons(
        self,
        stripe_invoice_id: str,
        stripe_account_id: str,
    ) -> dict[str, str]:
        """Retrieve the invoice with discounts expanded; return {di_id: coupon_id}."""
        opts = PaymentsStripeClient.connect_opts_readonly(stripe_account_id)
        retrieved = await self._stripe.v1.invoices.retrieve_async(
            stripe_invoice_id,
            params={"expand": ["discounts", "lines.data.discounts"]},
            options=opts,
        )
        coupon_by_discount: dict[str, str] = {}
        self._collect_coupons(
            getattr(retrieved, "discounts", None),
            coupon_by_discount,
        )
        lines = getattr(getattr(retrieved, "lines", None), "data", None) or []
        for line in lines:
            self._collect_coupons(
                getattr(line, "discounts", None),
                coupon_by_discount,
            )
        return coupon_by_discount

    def _collect_coupons(
        self,
        discounts: Any,
        coupon_by_discount: dict[str, str],
    ) -> None:
        """Add expanded Discount objects (di_ → coupon_id) into the map; skip bare id strings."""
        for discount in discounts or []:
            if isinstance(discount, str):
                continue
            discount_id = getattr(discount, "id", None)
            coupon_id = self._discount_coupon_id(discount)
            if discount_id and coupon_id:
                coupon_by_discount[discount_id] = coupon_id

    @staticmethod
    def _discount_coupon_id(discount: Any) -> str | None:
        """Coupon id from a Discount. Dahlia: source.coupon; legacy fallback: discount.coupon."""
        source = getattr(discount, "source", None)
        coupon = getattr(source, "coupon", None) if source is not None else None
        if isinstance(coupon, str):
            return coupon
        coupon_id = getattr(coupon, "id", None) if coupon is not None else None
        if coupon_id:
            return coupon_id
        legacy = getattr(discount, "coupon", None)
        if isinstance(legacy, str):
            return legacy
        return getattr(legacy, "id", None) if legacy is not None else None

    @staticmethod
    def _is_proration(line: dict[str, Any]) -> bool:
        """True if the line is a proration (dahlia parent fields; flat proration fallback)."""
        parent = line.get("parent")
        if isinstance(parent, dict):
            sub_details = parent.get("subscription_item_details")
            if isinstance(sub_details, dict) and sub_details.get("proration"):
                return True
            item_details = parent.get("invoice_item_details")
            if isinstance(item_details, dict) and item_details.get("proration"):
                return True
        return bool(line.get("proration"))

    @staticmethod
    def _lines(invoice: dict[str, Any]) -> list[dict[str, Any]]:
        lines = invoice.get("lines") or {}
        return list(lines.get("data") or [])
