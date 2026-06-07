"""Handler for Stripe ``refund.created`` / ``refund.updated`` events.

Stripe's 2026 "dahlia" generation dropped the ``refunds`` list from the charge
object, so ``charge.refunded`` no longer carries the refund details. Refunds
now arrive as their own ``refund.*`` events whose data object is the Refund
itself. This handler records each **succeeded** refund as a ``member_charges``
``refund`` row (negative amount) linked to the original payment via
``refunds_charge_id``.

Both ``refund.created`` and ``refund.updated`` route here: a card refund is
usually born ``succeeded`` (recorded on create), while an async refund is born
pending and only succeeds on a later update. We record on whichever event first
shows ``status='succeeded'``; the ``stripe_refund_id`` UNIQUE constraint
(``ON CONFLICT DO NOTHING``) makes the overlap idempotent.
"""

import logging
from typing import Any
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.shared.sql_loader import load_sql
from src.stripe_webhooks import SQL_DIR
from src.stripe_webhooks.service.stripe_json import dump_stripe_payload
from src.stripe_webhooks.service.stripe_time import stripe_ts_to_datetime

logger = logging.getLogger(__name__)

CHARGE_KIND_REFUND = "refund"
CHARGE_STATUS_SUCCEEDED = "succeeded"
REFUND_STATUS_SUCCEEDED = "succeeded"


class RefundHandler:
    """Record a succeeded Stripe refund against its original payment.

    The Refund object carries ``charge`` (the original charge id), which we
    match to the recorded ``member_charges`` payment row to attribute and link
    the refund. A refund whose original payment we never recorded is logged and
    acked (it needs manual reconciliation, not a Stripe retry loop).
    """

    async def handle(
        self,
        session: AsyncSession,
        event: dict[str, Any],
        gym_id: UUID,
    ) -> None:
        await self.absorb(session, event["data"]["object"], gym_id)

    async def absorb(
        self,
        session: AsyncSession,
        refund: dict[str, Any],
        gym_id: UUID,
    ) -> None:
        """Record a succeeded refund (Refund object) as a negative charge.

        The seam shared by the webhook dispatcher (``handle`` unwraps the event)
        and the reconciler invoice fetcher (passes the listed Refund directly).
        Idempotent via ``member_charges.stripe_refund_id`` UNIQUE.
        """
        if refund.get("status") != REFUND_STATUS_SUCCEEDED:
            # Pending/failed refunds are recorded once (if) they succeed.
            return

        stripe_refund_id = refund.get("id")
        stripe_charge_id = refund.get("charge")
        if not stripe_refund_id or not stripe_charge_id:
            raise ValueError(
                "refund event is missing refund id or charge id "
                f"(refund_id={stripe_refund_id}, charge={stripe_charge_id})"
            )

        parent = await self._find_parent_charge(
            session, stripe_charge_id, gym_id
        )
        if parent is None:
            # We never recorded the original payment — can't create a refund
            # row (invoice_id is NOT NULL). Log and ack; needs manual
            # reconciliation, not Stripe retries.
            logger.error(
                "refund: no parent payment row found "
                "(stripe_charge_id=%s, gym_id=%s); cannot record refund",
                stripe_charge_id,
                gym_id,
            )
            return

        insert_sql = load_sql(SQL_DIR / "member_charge_insert.sql")
        await session.execute(
            text(insert_sql),
            {
                "invoice_id": str(parent["invoice_id"]),
                "gym_id": str(gym_id),
                "member_id": str(parent["member_id"]),
                "kind": CHARGE_KIND_REFUND,
                "status": CHARGE_STATUS_SUCCEEDED,
                "amount": -int(refund.get("amount") or 0),
                "currency": refund.get("currency", "usd"),
                # A refund reverses the parent charge — carry its card so the
                # refund row shows which card the money went back to.
                "payment_method_type": parent.get("payment_method_type"),
                "card_last_four": parent.get("card_last_four"),
                "stripe_charge_id": None,
                "stripe_refund_id": stripe_refund_id,
                "refunds_charge_id": str(parent["charge_id"]),
                "charge_time": stripe_ts_to_datetime(refund.get("created")),
                "stripe_event_payload": dump_stripe_payload(refund),
            },
        )

    async def _find_parent_charge(
        self,
        session: AsyncSession,
        stripe_charge_id: str,
        gym_id: UUID,
    ) -> dict[str, Any] | None:
        lookup_sql = load_sql(SQL_DIR / "member_charge_by_stripe_charge_id.sql")
        result = await session.execute(
            text(lookup_sql),
            {
                "stripe_charge_id": stripe_charge_id,
                "gym_id": str(gym_id),
            },
        )
        row = result.mappings().fetchone()
        return dict(row) if row else None
