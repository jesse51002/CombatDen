"""Paginated payment history for the member-detail screen.

A standalone read so the (potentially long) charge history is fetched on
demand and windowed, rather than bundled into the member-detail response.
Returns the invoices the member PAID (paid_by_member_id), the invoices a
membership they have ever held was on (by membership item_id), and the
invoices that were FOR them (their id in the invoice's paid_for) — each row
labelled with the payer (paid_by_*) and the beneficiaries (paid_for).
"""

from __future__ import annotations

from uuid import UUID

from sqlalchemy import text

from src.members import SQL_DIR
from src.members.schema.members_billing_schema import (
    BillingDiscountInfo,
    BillingInvoiceAttempt,
    BillingLineItemRecord,
    BillingPaidForMember,
    BillingPaymentRecord,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

_PAYMENTS_SQL = SQL_DIR / "member_details" / "member_payments.sql"


class MembersPaymentsService:
    """Lists a member's payment history, paginated."""

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    async def list_payments(
        self,
        member_id: UUID,
        limit: int,
        offset: int,
    ) -> list[BillingPaymentRecord]:
        """Return one page of payment records, newest first.

        Args:
            member_id: The member whose history to read (gym and the
                member's membership item_ids are resolved from this member).
            limit: Max rows to return.
            offset: Rows to skip (page = offset / limit).

        Returns:
            A page of payment records — the charges that paid for any
            membership this member has held, plus their own direct charges,
            each with payer details.
        """
        sql = load_sql(_PAYMENTS_SQL)
        params = {
            "member_id": str(member_id),
            # Separate text-typed bind for the paid_for JSONB membership check
            # (jsonb_exists wants text; reusing :member_id, used in uuid
            # comparisons, would make asyncpg deduce conflicting types for it).
            "member_id_text": str(member_id),
            "limit": limit,
            "offset": offset,
        }
        async with self._db_pool.session() as session:
            result = await session.execute(text(sql), params)
            return [self._to_record(row) for row in result.mappings().all()]

    @staticmethod
    def _to_record(row: dict) -> BillingPaymentRecord:
        """Map one query row to a BillingPaymentRecord."""
        line_items = [
            BillingLineItemRecord(
                line_item_id=li["line_item_id"],
                item_type=li["item_type"],
                name=li["name"],
                amount=li["amount"],
                quantity=li.get("quantity") or 1,
                stripe_product_id=li.get("stripe_product_id"),
                item_id=(UUID(li["item_id"]) if li.get("item_id") else None),
                owner_label=li.get("owner_label"),
            )
            for li in (row["line_items"] or [])
        ]
        applied = [
            BillingDiscountInfo(
                stripe_coupon_id=ad["stripe_coupon_id"],
                amount_off=ad["amount_off"],
            )
            for ad in (row["applied_discounts"] or [])
        ]
        attempts = [
            BillingInvoiceAttempt(
                charge_id=at["charge_id"],
                kind=at["kind"],
                status=at["status"],
                amount=at["amount"],
                payment_method_type=at.get("payment_method_type"),
                card_last_four=at.get("card_last_four"),
                charge_time=at["charge_time"],
            )
            for at in (row["attempts"] or [])
        ]
        paid_for = [
            BillingPaidForMember(
                member_id=UUID(pf["member_id"]),
                first_name=pf["first_name"],
                last_name=pf["last_name"],
                photo_url=pf.get("photo_url"),
            )
            for pf in (row["paid_for"] or [])
        ]
        return BillingPaymentRecord(
            charge_id=row["charge_id"],
            invoice_id=row["invoice_id"],
            kind=row["kind"],
            status=row["status"],
            amount=row["amount"],
            currency=row["currency"],
            payment_method_type=row["payment_method_type"],
            charge_time=row["charge_time"],
            refunds_charge_id=row["refunds_charge_id"],
            refunded_amount=row["refunded_amount"] or 0,
            paid_by_member_id=row["paid_by_member_id"],
            paid_by_first_name=row["paid_by_first_name"],
            paid_by_last_name=row["paid_by_last_name"],
            paid_by_photo_url=row["paid_by_photo_url"],
            paid_for=paid_for,
            line_items=line_items,
            applied_discounts=applied,
            attempts=attempts,
        )
