"""Settle a recurring membership's OPEN Stripe invoice.

The shared body behind BOTH the cash settle (``mark_paid_cash``) and the card
retry (``retry_card``). The only thing those two differ on is HOW the invoice
is paid — out of band for cash, on the saved default card for a retry — so
that single step is passed in as ``pay`` and everything else (the validations,
the payer/subscription/account resolution, and applying the paid invoice back
to the CRM) lives here once.

Applying the paid invoice is done SYNCHRONOUSLY, right after paying — NOT via
the fire-and-forget on-demand fetch. A settle pays a specific open invoice,
usually a failed renewal created weeks ago; the on-demand ``fetch_for_payer``
only ever looks at invoices created at/after the op and the reconciler's
lookback window is far too short to reach it, so without the direct apply the
paid invoice would advance ``next_due_date`` and finalize the invoice/charge
rows only when the ``invoice.paid`` webhook happened to land (never on
localhost). ``pay`` returns the invoice it just marked paid and
``apply_invoice`` records THAT invoice BY VALUE through the same idempotent
``record()`` seam the webhook uses — no re-retrieve, so no window where a stale
read could book the collected charge as a failed attempt — and a later webhook
re-applying it is a clean no-op.

The in-request apply is best-effort ON TOP OF a completed charge: the money has
already moved by the time we apply, so an apply failure is logged and swallowed
(the webhook + reconciler remain the backstop) rather than surfaced as a failed
settle — surfacing it would tell staff nothing was collected and invite a
double collection.
"""

from __future__ import annotations

import logging
from collections.abc import Awaitable, Callable
from typing import TYPE_CHECKING
from uuid import UUID

from schema.membership_plan import PlanType

import src.shared.db_schema_path  # noqa: F401
from src.memberships.service.memberships_base import (
    MemberMembershipsBase,
)
from src.shared.database import DirectDatabasePool
from src.shared.gym_timezone import gym_today

if TYPE_CHECKING:
    from src.memberships.service.memberships_invoice_fetch import (
        MemberMembershipsInvoiceFetch,
    )
    from src.shared.gym_stripe_service import GymStripeService
    from src.shared.payer_resolver import PayerResolver
    from src.sync.service.sync_service import (
        PaymentSyncService,
    )

logger = logging.getLogger(__name__)

# Pays ONE open invoice on a subscription and returns that now-paid invoice as
# the plain nested dict the record seam consumes. The card / cash difference is
# entirely captured by which of these is passed.
PayOpenInvoice = Callable[..., Awaitable[dict]]


class MemberMembershipsSettle(MemberMembershipsBase):
    """Validate, pay, and apply a recurring membership's open invoice."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        payment_sync_service: PaymentSyncService,
        gym_stripe_service: GymStripeService,
        payer_resolver: PayerResolver,
        invoice_fetch: MemberMembershipsInvoiceFetch,
    ) -> None:
        super().__init__(
            db_pool,
            payment_sync_service,
            gym_stripe_service,
        )
        self._payer_resolver = payer_resolver
        self._invoice_fetch = invoice_fetch

    async def settle_open_invoice(
        self,
        item_id: UUID,
        member_id: UUID,
        idempotency_key: UUID,
        *,
        pay: PayOpenInvoice,
    ) -> None:
        """Settle the membership's subscription's open invoice.

        Validates the membership is recurring, linked to a Stripe
        subscription, and not canceled; resolves the membership's PAYER (the
        row's ``paid_by_member_id``) to its monthly subscription; pays that
        subscription's open invoice via ``pay``; then applies the paid invoice
        to the CRM synchronously so ``next_due_date`` and the invoice/charge
        rows are up to date before this returns. The apply is best-effort — the
        charge has already completed, so an apply failure is logged and
        swallowed (the webhook + reconciler finalize the rows), never raised.

        Args:
            item_id: The membership row id.
            member_id: The member who owns the membership row.
            idempotency_key: Money-op idempotency key, threaded to Stripe.
            pay: How to pay the open invoice —
                ``pay_open_subscription_invoice_out_of_band`` (cash) or
                ``pay_open_subscription_invoice_on_card`` (retry).

        Raises:
            ValueError: If the membership is not recurring, is canceled, not
                linked to a Stripe subscription, or has no open invoice.
            PaymentsStripeError / stripe.CardError: On a Stripe failure.
        """
        membership = await self._get_membership(item_id, member_id)

        if PlanType(membership["plan_type"]) != PlanType.recurring:
            raise ValueError(
                "Only recurring memberships have a subscription invoice to settle"
            )
        if not membership["stripe_item_id"]:
            raise ValueError(
                f"Membership {item_id} is not linked to a Stripe subscription"
            )
        cancel_date = membership["cancel_date"]
        if cancel_date is not None and cancel_date <= gym_today(
            membership["timezone"]
        ):
            raise ValueError(
                "Cannot settle a canceled membership; "
                "create a new membership instead"
            )

        payer = await self._payer_resolver.resolve_payer(
            membership["paid_by_member_id"],
        )
        if not payer.stripe_sub_id_month:
            raise ValueError(
                f"No active monthly subscription for payer {payer.member_id}",
            )

        stripe_account_id = await self._gym_stripe.get_stripe_account_id(
            payer.gym_id,
        )

        invoice = await pay(
            payer.stripe_sub_id_month,
            stripe_account_id,
            idempotency_key=str(idempotency_key),
        )

        # Apply the exact invoice we just paid, in-request. The card was
        # ALREADY charged above, so a failure HERE must not surface as a failed
        # settle — that would tell staff nothing was collected and invite a
        # double collection. Swallow it (logged) and let the invoice.paid
        # webhook + reconciler finalize next_due_date / the CRM rows, exactly
        # as the pre-in-request settle relied on them.
        try:
            await self._invoice_fetch.apply_invoice(
                payer.gym_id, stripe_account_id, invoice
            )
        except Exception:
            logger.error(
                "Settle charged invoice %s for member %s (item %s) but the "
                "in-request apply failed; next_due_date / the CRM invoice+"
                "charge rows will be finalized by the invoice.paid webhook + "
                "reconciler backstop",
                invoice.get("id"),
                member_id,
                item_id,
                exc_info=True,
            )
