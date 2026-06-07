"""Paginated payment history for the member-detail screen.

A standalone read so the (potentially long) charge history is fetched on
demand and windowed, rather than bundled into the member-detail response.
Attributed by membership: returns the charges whose invoice covers one of
the memberships this member has ever held (by membership item_id), plus the
member's own directly-billed invoices — each labelled with who was charged.
"""

from __future__ import annotations

from uuid import UUID

from sqlalchemy import text

from src.members import SQL_DIR
from src.members.schema.members_billing_schema import (
    BillingDiscountInfo,
    BillingLineItemRecord,
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
            )
            for li in (row["line_items"] or [])
        ]
        applied = [
            BillingDiscountInfo(
                discount_id=ad["discount_id"],
                discount_name=ad["discount_name"],
                discount_type=ad["discount_type"],
                percentage_off=ad.get("percentage_off"),
                dollar_off=ad.get("dollar_off"),
            )
            for ad in (row["applied_discounts"] or [])
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
            line_items=line_items,
            applied_discounts=applied,
        )
