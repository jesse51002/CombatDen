"""Shared attribution resolver for subscription invoices.

A standalone concern module (free functions by design) so the
``invoice.paid`` and ``invoice.payment_failed`` handlers resolve a
subscription invoice's payer + beneficiaries through ONE code path — a
fix here (e.g. the consolidated co-owner gathering) can't be applied to
only one copy.
"""

from __future__ import annotations

from typing import Any
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.shared.sql_loader import load_sql
from src.stripe_webhooks import SQL_DIR
from src.stripe_webhooks.service.stripe_invoice_fields import (
    line_subscription_item,
)


async def resolve_subscription_attribution(
    session: AsyncSession,
    lines: list[dict[str, Any]],
    gym_id: UUID,
) -> tuple[UUID | None, list[UUID]]:
    """Resolve ``(paid_by_member_id, paid_for)`` from a subscription
    invoice's lines.

    Matches each line's ``subscription_item`` against ``member_memberships``
    and gathers **every** owner the item bills — a consolidated item
    (quantity > 1) maps to several co-owners at one price, so all are
    collected (not just the first). The payer is the membership's
    ``paid_by_member_id`` (one Stripe subscription = one payer). Returns
    ``(None, [])`` when no line resolves.
    """
    membership_sql = load_sql(SQL_DIR / "memberships_by_stripe_item.sql")
    paid_by_member_id: UUID | None = None
    paid_for: list[UUID] = []
    seen: set[UUID] = set()
    for line in lines:
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
        for row in result.mappings().all():
            owner = UUID(str(row["member_id"]))
            if owner not in seen:
                seen.add(owner)
                paid_for.append(owner)
            if paid_by_member_id is None:
                paid_by_member_id = UUID(str(row["paid_by_member_id"]))
    return paid_by_member_id, paid_for
