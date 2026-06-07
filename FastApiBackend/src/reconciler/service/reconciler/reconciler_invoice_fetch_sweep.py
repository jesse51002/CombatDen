"""InvoiceFetchSweep — backfill missed billing webhooks from Stripe.

A missed-webhook backstop. Per gym Connect account it lists the last
``RECONCILER_INVOICE_LOOKBACK_DAYS`` of Stripe activity and re-absorbs each
object through the SAME handler ``absorb`` methods the webhook dispatcher uses --
but driving objects from list calls instead of events, so it cannot rely on the
event-log dedup. Idempotency therefore comes from the DB layer: the invoice
upsert (``stripe_invoice_id``), the succeeded-charge UNIQUE (``stripe_charge_id``),
the refund UNIQUE (``stripe_refund_id``), and the failed-charge synthetic
per-attempt key.

For each invoice: a paid invoice records the bill (+ line items + next_due_date,
which is what clears a falsely-overdue member) and then its succeeded payments
record the charge rows; an open invoice that has been attempted records the
failed-attempt charge. Refunds are listed per account and recorded as negative
charges. Each object is absorbed in its own DB transaction so one bad object
cannot roll back the rest; ``SubscriptionItemPendingError`` /
``InvoiceNotYetRecordedError`` are caught per object and retried next sweep.
"""

import logging
import time
from collections.abc import AsyncGenerator, Awaitable, Callable
from typing import Any
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.core.config import (
    RECONCILER_INVOICE_LOOKBACK_DAYS,
    RECONCILER_STRIPE_PAGE_SIZE,
)
from src.payments.service.payments_stripe_client import PaymentsStripeClient
from src.reconciler import SQL_DIR
from src.reconciler.service.reconciler.reconciler_result import SweepResult
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql
from src.stripe_webhooks.service.invoice_paid_handler import InvoicePaidHandler
from src.stripe_webhooks.service.invoice_payment_failed_handler import (
    InvoicePaymentFailedHandler,
)
from src.stripe_webhooks.service.invoice_payment_paid_handler import (
    InvoicePaymentPaidHandler,
)
from src.stripe_webhooks.service.refund_handler import RefundHandler
from src.stripe_webhooks.stripe_webhooks_exceptions import (
    InvoiceNotYetRecordedError,
    SubscriptionItemPendingError,
)

logger = logging.getLogger(__name__)

SWEEP_NAME = "invoice_fetch"
SECONDS_PER_DAY = 86400
INVOICE_STATUS_PAID = "paid"
INVOICE_STATUS_OPEN = "open"
PAYMENT_STATUS_PAID = "paid"


class InvoiceFetchSweep:
    """Re-absorb recent Stripe invoices / payments / refunds per gym."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        stripe_client: PaymentsStripeClient,
        invoice_paid_handler: InvoicePaidHandler,
        invoice_payment_paid_handler: InvoicePaymentPaidHandler,
        invoice_payment_failed_handler: InvoicePaymentFailedHandler,
        refund_handler: RefundHandler,
    ) -> None:
        self._db_pool = db_pool
        self._stripe = stripe_client.client
        self._invoice_paid = invoice_paid_handler
        self._invoice_payment_paid = invoice_payment_paid_handler
        self._invoice_payment_failed = invoice_payment_failed_handler
        self._refund = refund_handler

    async def run(self) -> SweepResult:
        """Sweep recent Stripe activity for every connected gym."""
        result = SweepResult(name=SWEEP_NAME)
        cutoff = (
            int(time.time())
            - RECONCILER_INVOICE_LOOKBACK_DAYS * SECONDS_PER_DAY
        )
        gyms = await self._list_gyms()
        for gym in gyms:
            await self._sweep_gym(
                gym["gym_id"],
                gym["stripe_account_id"],
                cutoff,
                result,
            )
        logger.info(
            "Invoice fetch: gyms=%d processed=%d absorbed=%d "
            "skipped=%d errors=%d",
            len(gyms),
            result.processed,
            result.changed,
            result.skipped,
            result.errors,
        )
        return result

    async def _list_gyms(self) -> list[dict]:
        """Gyms that have a Stripe Connect account."""
        sql = load_sql(SQL_DIR / "reconciler_gyms_with_connect.sql")
        async with self._db_pool.session() as session:
            res = await session.execute(text(sql))
            return [dict(row) for row in res.mappings().all()]

    async def _sweep_gym(
        self,
        gym_id: UUID,
        account_id: str,
        cutoff: int,
        result: SweepResult,
    ) -> None:
        """List + absorb one gym's recent invoices and refunds."""
        opts = PaymentsStripeClient.connect_opts_readonly(account_id)
        created = {"created": {"gte": cutoff}, "limit": RECONCILER_STRIPE_PAGE_SIZE}

        async for invoice in self._iter(
            self._stripe.v1.invoices.list_async, created, opts
        ):
            await self._absorb_invoice(
                invoice, gym_id, account_id, opts, result
            )

        async for refund in self._iter(
            self._stripe.v1.refunds.list_async, created, opts
        ):
            result.processed += 1
            await self._absorb_in_txn(
                result,
                lambda s, r=refund: self._refund.absorb(s, r, gym_id),
            )

    async def _absorb_invoice(
        self,
        invoice: Any,
        gym_id: UUID,
        account_id: str,
        opts: Any,
        result: SweepResult,
    ) -> None:
        """Route one invoice to the bill / failed-attempt absorber."""
        status = invoice.get("status")
        if status == INVOICE_STATUS_PAID:
            result.processed += 1
            await self._absorb_in_txn(
                result,
                lambda s: self._invoice_paid.absorb(
                    s, invoice, gym_id, stripe_account_id=account_id
                ),
            )
            await self._absorb_invoice_payments(
                invoice, gym_id, account_id, opts, result
            )
        elif (
            status == INVOICE_STATUS_OPEN
            and int(invoice.get("attempt_count") or 0) > 0
        ):
            result.processed += 1
            await self._absorb_in_txn(
                result,
                lambda s: self._invoice_payment_failed.absorb(
                    s, invoice, gym_id
                ),
            )

    async def _absorb_invoice_payments(
        self,
        invoice: Any,
        gym_id: UUID,
        account_id: str,
        opts: Any,
        result: SweepResult,
    ) -> None:
        """Record each succeeded payment of a paid invoice as a charge."""
        params = {
            "invoice": invoice["id"],
            "limit": RECONCILER_STRIPE_PAGE_SIZE,
        }
        async for payment in self._iter(
            self._stripe.v1.invoice_payments.list_async, params, opts
        ):
            if payment.get("status") != PAYMENT_STATUS_PAID:
                continue
            result.processed += 1
            await self._absorb_in_txn(
                result,
                lambda s, p=payment: self._invoice_payment_paid.absorb(
                    s, p, gym_id, stripe_account_id=account_id
                ),
            )

    async def _absorb_in_txn(
        self,
        result: SweepResult,
        absorb: Callable[[AsyncSession], Awaitable[None]],
    ) -> None:
        """Run one absorb in its own transaction; count + isolate failures."""
        try:
            async with self._db_pool.session() as session, session.begin():
                await absorb(session)
            result.changed += 1
        except (SubscriptionItemPendingError, InvoiceNotYetRecordedError):
            # Not yet resolvable (the bill/membership isn't recorded) -- the
            # next sweep retries once it is.
            result.skipped += 1
        except Exception:
            logger.error(
                "Invoice fetch: absorb failed; continuing",
                exc_info=True,
            )
            result.errors += 1

    async def _iter(
        self,
        list_fn: Callable[..., Awaitable[Any]],
        base_params: dict[str, Any],
        opts: Any,
    ) -> AsyncGenerator[Any]:
        """Yield every object across a paginated Stripe list."""
        starting_after: str | None = None
        while True:
            params = dict(base_params)
            if starting_after:
                params["starting_after"] = starting_after
            page = await list_fn(params=params, options=opts)
            data = list(page.data)
            for obj in data:
                yield obj
            if not data or not getattr(page, "has_more", False):
                break
            starting_after = data[-1].id
