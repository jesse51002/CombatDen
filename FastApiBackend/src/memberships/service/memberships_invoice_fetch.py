"""Deterministic invoice fetch: pull a payer's (or a whole account's) recent
Stripe invoices / payments / refunds and apply them through the SAME idempotent
webhook ``record`` seams.

Two callers, one engine:
  - **on-demand** (``fetch_for_payer``): fired fire-and-forget right after an
    invoice-creating membership op, so the bill lands in our DB WITHOUT waiting
    on the ``invoice.paid`` / ``invoice_payment.paid`` webhooks (slow / risky).
  - **reconciler backstop** (``sweep_account`` with ``customer=None``): the
    twice-daily full sweep delegates here per gym.

The fetch + apply loop lives HERE (memberships); the reconciler calls in, never
the reverse. Stripe is reached ONLY through the payments layer — the
``PaymentsStripePaymentService`` list primitives (this service never touches the
Stripe client itself); the webhook ``record`` handlers stay in
``stripe_webhooks`` and are injected.

Idempotency is at the DB layer (invoice upsert on ``stripe_invoice_id``,
succeeded-charge UNIQUE on ``stripe_charge_id``, refund UNIQUE, failed-charge
synthetic per-attempt key), so a post-op fetch racing the webhook OR the cron
sweep is safe — whichever lands first wins, the rest are no-ops. Each object is
recorded in its OWN DB transaction so one bad object cannot roll back the rest.
"""

import asyncio
import logging
from collections.abc import Awaitable, Callable
from uuid import UUID

from pydantic import ValidationError
from sqlalchemy.ext.asyncio import AsyncSession

from src.core.config import settings
from src.payments.service.payments_stripe_payment_service import (
    PaymentsStripePaymentService,
)
from src.shared.database import DirectDatabasePool
from src.shared.payer_resolver import PayerResolver
from src.shared.sweep_result import SweepResult
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

ON_DEMAND_NAME = "invoice_fetch_on_demand"
INVOICE_STATUS_PAID = "paid"
INVOICE_STATUS_OPEN = "open"
PAYMENT_STATUS_PAID = "paid"


class MemberMembershipsInvoiceFetch:
    """Fetch + apply recent Stripe invoices for one customer or a whole account."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        payment_service: PaymentsStripePaymentService,
        invoice_paid_handler: InvoicePaidHandler,
        invoice_payment_paid_handler: InvoicePaymentPaidHandler,
        invoice_payment_failed_handler: InvoicePaymentFailedHandler,
        refund_handler: RefundHandler,
        payer_resolver: PayerResolver,
    ) -> None:
        self._db_pool = db_pool
        # Stripe is reached only through this — no raw client here.
        self._payments = payment_service
        self._invoice_paid = invoice_paid_handler
        self._invoice_payment_paid = invoice_payment_paid_handler
        self._invoice_payment_failed = invoice_payment_failed_handler
        self._refund = refund_handler
        self._payer_resolver = payer_resolver

    # ── On-demand per-payer (the post-op fast path) ──────────────────

    async def fetch_for_payer(
        self,
        payer_member_id: UUID,
        op_start: int,
    ) -> None:
        """Deterministically pull + apply one payer's new invoices.

        Resolves the payer's Stripe customer + Connect account, then lists that
        customer's invoices created since ``op_start`` (minus a clock-skew
        buffer) and applies each. Retries on a short bounded schedule because a
        just-created invoice may not be ``paid`` / listable the instant the op
        returns; stops early once it applies a paid invoice created AT/AFTER the
        op (``created >= op_start``) — i.e. the bill THIS op cut, not a stale
        one already in the lookback window.

        Best-effort: a payer with no billing profile (cash-only / engagement
        member) is a clean no-op. The webhook + cron sweep remain backstops.
        """
        try:
            payer, account_id = (
                await self._payer_resolver.resolve_payer_with_account(
                    payer_member_id
                )
            )
        except (ValueError, ValidationError):
            logger.debug(
                "Invoice fetch: payer %s has no billing profile; skipping",
                payer_member_id,
            )
            return

        cutoff = op_start - settings.invoice_fetch_buffer_seconds
        result = SweepResult(name=ON_DEMAND_NAME)
        fresh: list[str] = []
        for delay in settings.invoice_fetch_retry_delays_seconds:
            before = len(fresh)
            await self.sweep_account(
                payer.gym_id,
                account_id,
                cutoff,
                result,
                customer=payer.stripe_customer_id,
                fresh=fresh,
                fresh_since=op_start,
            )
            if len(fresh) > before:
                return  # applied the bill this op cut — done
            if delay:
                # CancelledError propagates on shutdown — do not swallow.
                await asyncio.sleep(delay)

    # ── Per-account loop (the reconciler delegates here) ─────────────

    async def sweep_account(
        self,
        gym_id: UUID,
        account_id: str,
        cutoff: int,
        result: SweepResult,
        *,
        customer: str | None = None,
        fresh: list[str] | None = None,
        fresh_since: int | None = None,
    ) -> None:
        """List + record an account's recent invoices (and refunds).

        ``customer`` scopes the invoice fetch to one Stripe customer (the
        on-demand post-op path); ``None`` sweeps the whole account (the
        reconciler backstop). ``fresh`` / ``fresh_since`` (on-demand only) record
        the ids of paid invoices created ``>= fresh_since`` so the caller can
        early-stop. Mutates ``result`` in place. All Stripe I/O goes through the
        payments service.
        """
        page_size = settings.reconciler_stripe_page_size
        invoices = await self._payments.list_invoices(
            account_id,
            created_gte=cutoff,
            limit=page_size,
            customer=customer,
        )
        for invoice in invoices:
            await self._record_invoice(
                invoice,
                gym_id,
                account_id,
                result,
                fresh=fresh,
                fresh_since=fresh_since,
            )

        # Refunds are listed account-wide (refunds.list has NO customer filter)
        # and only on the full sweep — the customer-scoped on-demand fetch is
        # about a new invoice / charge, not refunds (which have their own op +
        # webhook + the cron backstop).
        if customer is None:
            refunds = await self._payments.list_refunds(
                account_id,
                created_gte=cutoff,
                limit=page_size,
            )
            for refund in refunds:
                result.processed += 1
                await self._run_record(
                    result,
                    lambda s, r=refund: self._refund.record(s, r, gym_id),
                )

    async def apply_invoice(
        self,
        gym_id: UUID,
        account_id: str,
        invoice_id: str,
    ) -> None:
        """Apply ONE known invoice to the CRM, synchronously and by id.

        The settle path (retry-card / mark-paid-cash) pays a specific OPEN
        invoice — usually a failed renewal created weeks ago. The on-demand
        `fetch_for_payer` cannot pick that up (it lists only invoices created
        at/after the op), and the reconciler's lookback window is far too
        short to reach it, so without this the paid invoice would advance
        `next_due_date` and finalize the invoice/charge rows only when the
        `invoice.paid` webhook happens to land (never on localhost). This
        retrieves the exact invoice and routes it through the SAME idempotent
        `_record_invoice` seam the webhook and sweep use, so a later webhook
        re-applying it is a clean no-op.
        """
        invoice = await self._payments.retrieve_invoice(invoice_id, account_id)
        result = SweepResult(name=ON_DEMAND_NAME)
        await self._record_invoice(invoice, gym_id, account_id, result)

    async def _record_invoice(
        self,
        invoice: dict,
        gym_id: UUID,
        account_id: str,
        result: SweepResult,
        *,
        fresh: list[str] | None = None,
        fresh_since: int | None = None,
    ) -> None:
        """Route one invoice to the bill / failed-attempt recorder."""
        status = invoice.get("status")
        if status == INVOICE_STATUS_PAID:
            await self._complete_invoice_lines(invoice, account_id)
            result.processed += 1
            applied = await self._run_record(
                result,
                lambda s: self._invoice_paid.record(
                    s, invoice, gym_id, stripe_account_id=account_id
                ),
            )
            if (
                applied
                and fresh is not None
                and fresh_since is not None
                and int(invoice.get("created") or 0) >= fresh_since
            ):
                fresh.append(invoice["id"])
            await self._record_invoice_payments(invoice, gym_id, account_id, result)
        elif (
            status == INVOICE_STATUS_OPEN
            and int(invoice.get("attempt_count") or 0) > 0
        ):
            result.processed += 1
            await self._run_record(
                result,
                lambda s: self._invoice_payment_failed.record(
                    s, invoice, gym_id
                ),
            )

    async def _complete_invoice_lines(
        self,
        invoice: dict,
        account_id: str,
    ) -> None:
        """Ensure a paid invoice carries ALL its line items before recording.

        ``invoices.list`` (and the webhook payload) inline only the first page
        of ``lines``; an invoice with more lines than the page size reports
        ``lines.has_more``. The record seam inserts one row per line and advances
        each line's membership dates, so the remaining lines must be paginated in
        (via the payments line-items primitive) and merged before recording — else
        a large consolidated/family invoice would silently drop lines past the
        first page.
        """
        lines = invoice.get("lines") or {}
        if not lines.get("has_more"):
            return
        invoice_id = invoice.get("id")
        if not invoice_id:
            return
        full = await self._payments.list_invoice_line_items(
            account_id,
            invoice_id,
            limit=settings.reconciler_stripe_page_size,
        )
        if full:
            lines["data"] = full
            lines["has_more"] = False
            invoice["lines"] = lines

    async def _record_invoice_payments(
        self,
        invoice: dict,
        gym_id: UUID,
        account_id: str,
        result: SweepResult,
    ) -> None:
        """Record each succeeded payment of a paid invoice as a charge."""
        payments = await self._payments.list_invoice_payments(
            account_id,
            invoice["id"],
            limit=settings.reconciler_stripe_page_size,
        )
        for payment in payments:
            if payment.get("status") != PAYMENT_STATUS_PAID:
                continue
            result.processed += 1
            await self._run_record(
                result,
                lambda s, p=payment: self._invoice_payment_paid.record(
                    s, p, gym_id, stripe_account_id=account_id
                ),
            )

    async def _run_record(
        self,
        result: SweepResult,
        record: Callable[[AsyncSession], Awaitable[None]],
    ) -> bool:
        """Run one record in its own transaction; count + isolate failures.

        Returns ``True`` when the record applied (so the caller can mark a paid
        invoice as freshly recorded for early-stop).
        """
        try:
            async with self._db_pool.session() as session, session.begin():
                await record(session)
            result.changed += 1
            return True
        except (SubscriptionItemPendingError, InvoiceNotYetRecordedError):
            # Not yet resolvable (the bill / membership isn't recorded) -- a
            # later retry (or the next sweep) applies it once it is.
            result.skipped += 1
            return False
        except Exception:
            logger.error(
                "Invoice fetch: record failed; continuing",
                exc_info=True,
            )
            result.errors += 1
            return False
