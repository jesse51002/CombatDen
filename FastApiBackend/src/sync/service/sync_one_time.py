"""Charge a payer's PENDING one-time memberships on one consolidated invoice.

A one-time membership is billed by a single invoice line, discounted at creation
and **terminal** (charged exactly once). This service is the one-time counterpart
of the recurring ``PaymentSyncService`` — but a one-shot charge, not a
re-derive-and-converge reconciler. It **reuses** the recurring engine's shared
pieces (the read queries and ``PaymentSyncDiscounts.resolve`` — the discount math,
unchanged) and leaves ``PaymentSyncService`` untouched.

Each membership is its own invoice line (its own line id + its exact discount): a
Stripe invoice has no one-item-per-price constraint like a subscription, so there
is no consolidation and no ÷quantity averaging — the discount engine is fed
per-membership (qty-1) groups, where its averaging is a no-op (÷1).
"""

import logging
from uuid import UUID

import src.shared.db_schema_path  # noqa: F401
from src.payments.schema.metadata.stripe_membership_one_time_metadata import (
    StripeMembershipOneTimeMetadata,
)
from src.payments.schema.payments_invoice_schema import (
    PreviewInvoice,
)
from src.payments.schema.payments_payment_schema import (
    PaymentsInvoiceItemSpec,
    PaymentsInvoicePaymentCreateRequest,
    PaymentsInvoicePaymentPreviewRequest,
    PaymentsInvoicePaymentResponse,
)
from src.payments.service.payments_stripe_payment_service import (
    PaymentsStripePaymentService,
)
from src.shared.database import DirectDatabasePool
from src.shared.gym_timezone import gym_today
from src.shared.payer_profile import PayerProfile
from src.shared.payer_resolver import PayerResolver
from src.sync.service.sync_discounts import (
    PaymentSyncDiscounts,
)
from src.sync.service.sync_queries import (
    PaymentSyncQueries,
)
from src.sync.sync_schema import (
    ActiveMembershipRow,
    OneTimeInvoiceItem,
    OneTimeInvoicePlan,
)

logger = logging.getLogger(__name__)


class PaymentSyncOneTime:
    """Charge a payer's pending one-time memberships (own invoice, reuses resolve).

    Independent of ``PaymentSyncService`` (recurring): own read filter + own
    per-membership grouping + own invoice execute + own writeback, sharing only
    the read queries and the discount resolution.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        discounts: PaymentSyncDiscounts,
        payment_service: PaymentsStripePaymentService,
        payer_resolver: PayerResolver,
    ) -> None:
        self._queries = PaymentSyncQueries(db_pool)
        self._discounts = discounts
        self._payments = payment_service
        self._payer = payer_resolver

    async def charge_one_time(
        self,
        payer_member_id: UUID,
        idempotency_key: UUID,
        paid_with_cash: bool = False,
        payment_method_id: str | None = None,
    ) -> None:
        """Charge the payer's PENDING one-time memberships on ONE invoice.

        Resolves the payer's own profile, builds the desired invoice (one line
        per pending one-time membership the payer bills, item-level discounts),
        charges it once on the payer's customer, and writes back each
        membership's line id + invoice id + price + the applied discounts. A
        **no-op** when the payer has no pending one-time memberships (never cuts
        an empty invoice). Returns ``None`` — the caller reads the DB (the
        ``applied`` status) to confirm. One-time memberships are terminal, so
        re-running finds no ``not_added`` rows and charges nothing again.

        ``payment_method_id`` charges a SPECIFIC one-off card (entered at
        checkout) instead of the payer's saved default — the payment service
        attaches → pays → detaches it (a one-off is never kept; saving a card as
        the default is a separate up-front step). Ignored on a cash settle.
        """
        payer, stripe_account_id = await self._payer.resolve_payer_with_account(
            payer_member_id,
        )
        plan = await self._build_plan(payer, stripe_account_id)
        if not plan.items:
            return
        result = await self._execute(
            plan,
            idempotency_key,
            paid_with_cash,
            payment_method_id,
        )
        await self._writeback(plan, result)

    async def preview_one_time(
        self,
        payer_member_id: UUID,
    ) -> PreviewInvoice | None:
        """Preview the payer's STAGED one-time invoice (no charge, no writes).

        The caller stages the membership(s) being previewed as ``preview_add``
        first; this reads that staged state (``preview=True``), resolves the
        coupons (idempotent gym-wide find-or-create), and returns the discounted
        invoice preview. ``None`` when nothing is staged. Writes nothing back.

        Stripe's ``invoices.create_preview`` previews the customer's NEXT
        invoice, so for a payer with a live subscription it returns the staged
        ad-hoc invoice-item lines AND the subscription's upcoming recurring
        lines. This preview is the ONE-TIME purchase only, so the
        subscription-derived lines are stripped (``_one_time_only``) and the
        totals recomputed from the kept lines before returning.
        """
        payer, stripe_account_id = await self._payer.resolve_payer_with_account(
            payer_member_id,
        )
        plan = await self._build_plan(payer, stripe_account_id, preview=True)
        if not plan.items:
            return None
        request = PaymentsInvoicePaymentPreviewRequest(
            stripe_customer_id=payer.stripe_customer_id,
            items=self._to_item_specs(plan),
        )
        preview = await self._payments.preview_invoice_payment(
            request,
            stripe_account_id,
        )
        return self._one_time_only(preview)

    @staticmethod
    def _one_time_only(preview: PreviewInvoice) -> PreviewInvoice:
        """Keep only the staged one-time invoice-item lines; recompute totals.

        A subscription-derived line carries a ``stripe_subscription_item_id``
        and/or the ``is_proration`` flag; a pure invoice-item (one-time) line
        carries neither. The customer-level preview mixes the live
        subscription's upcoming lines in with the staged invoice items, so this
        drops the subscription lines and rebuilds ``subtotal`` / ``total`` /
        ``amount_due`` from the kept ones — the discounted one-time sum the CRM
        renders. ``next_payment_date`` is dropped (it described the recurring
        cycle, which is no longer part of this preview).
        """
        kept = [
            line
            for line in preview.lines
            if line.stripe_subscription_item_id is None
            and not line.is_proration
        ]
        subtotal = sum(line.amount for line in kept)
        total = sum(line.discounted_amount for line in kept)
        return PreviewInvoice(
            amount_due=total,
            subtotal=subtotal,
            total=total,
            currency=preview.currency,
            lines=kept,
            next_payment_date=None,
        )

    async def _build_plan(
        self,
        payer: PayerProfile,
        stripe_account_id: str,
        preview: bool = False,
    ) -> OneTimeInvoicePlan:
        """Read the payer's PENDING one-time memberships → the desired invoice.

        One invoice line **per membership**: reads the payer's one-time rows
        (``not_added``, plus ``preview_add`` when ``preview``) each carrying its
        discounts, groups
        them one-per-membership so the **unchanged** ``PaymentSyncDiscounts.resolve``
        runs ÷1 (no averaging — each membership keeps its exact discount), and
        assembles the ordered ``OneTimeInvoicePlan`` (one item per membership,
        item-level coupons percent→dollar) plus the ``applied_discount_id →
        coupon_id`` links. No DB writes (coupon find-or-create is an idempotent
        gym-wide Stripe op).
        """
        today = gym_today(payer.timezone)
        memberships = await self._queries.get_active_one_time(
            payer.member_id, today, preview
        )
        groups = self._group_per_membership(memberships)

        resolved = await self._discounts.resolve(groups, stripe_account_id)

        items = [
            OneTimeInvoiceItem(
                item_id=membership.item_id,
                member_id=membership.member_id,
                plan_id=membership.plan_id,
                stripe_price_id=membership.stripe_price_id,
                quantity=membership.quantity,
                coupon_ids=[
                    discount.coupon
                    for discount in resolved.coupons_by_price.get(
                        membership.item_id, []
                    )
                ],
            )
            for membership in memberships
        ]
        return OneTimeInvoicePlan(
            items=items,
            payer=payer,
            stripe_account_id=stripe_account_id,
            coupon_links=resolved.links,
        )

    @staticmethod
    def _group_per_membership(
        memberships: list[ActiveMembershipRow],
    ) -> dict[UUID, list[ActiveMembershipRow]]:
        """Group one-time memberships ONE-per-group, keyed by ``item_id``.

        Each membership is its own invoice line (its own line id + its own
        item-level discount) — a Stripe invoice has no one-item-per-price
        constraint like a subscription, so we never consolidate or average across
        members. A singleton group makes the shared discount math's ÷quantity a
        no-op (÷1), so ``resolve`` is reused unchanged.
        """
        return {membership.item_id: [membership] for membership in memberships}

    @staticmethod
    def _to_item_specs(
        plan: OneTimeInvoicePlan,
    ) -> list[PaymentsInvoiceItemSpec]:
        """One invoice-item spec per membership line (price + qty + coupons)."""
        return [
            PaymentsInvoiceItemSpec(
                stripe_price_id=item.stripe_price_id,
                quantity=item.quantity,
                coupon_ids=item.coupon_ids,
            )
            for item in plan.items
        ]

    @staticmethod
    def _beneficiaries(plan: OneTimeInvoicePlan) -> list[UUID]:
        """Distinct beneficiary owners across the invoice's membership lines.

        The payer (``plan.payer.member_id``) bills one or more memberships,
        each owned by a member (often the payer, sometimes a linked child).
        ``paid_for`` is that distinct owner set, in line order, so a one-time
        membership invoice surfaces on each beneficiary's page (not just the
        payer's).
        """
        seen: set[UUID] = set()
        out: list[UUID] = []
        for item in plan.items:
            if item.member_id not in seen:
                seen.add(item.member_id)
                out.append(item.member_id)
        return out

    async def _execute(
        self,
        plan: OneTimeInvoicePlan,
        idempotency_key: UUID,
        paid_with_cash: bool,
        payment_method_id: str | None = None,
    ) -> PaymentsInvoicePaymentResponse:
        """Charge the assembled invoice — one price line per membership.

        One consolidated invoice on the payer's customer (invoice-level metadata =
        the payer + the distinct beneficiary owners + gym; per-membership provenance
        rides each line's ``stripe_item_id`` after the writeback). ``line_item_ids``
        / ``line_amounts`` come back in the same order as ``plan.items``. When
        ``payment_method_id`` is set the payment service attaches that one-off card,
        charges it, and detaches it — the payer's saved default is never touched.
        """
        request = PaymentsInvoicePaymentCreateRequest(
            stripe_customer_id=plan.payer.stripe_customer_id,
            items=self._to_item_specs(plan),
            metadata=StripeMembershipOneTimeMetadata(
                paid_by_member_id=plan.payer.member_id,
                paid_for=self._beneficiaries(plan),
                gym_id=plan.payer.gym_id,
            ),
            paid_out_of_band=paid_with_cash,
            payment_method_id=payment_method_id,
            idempotency_key=str(idempotency_key),
        )
        return await self._payments.create_invoice_payment(
            request,
            plan.stripe_account_id,
        )

    async def _writeback(
        self,
        plan: OneTimeInvoicePlan,
        result: PaymentsInvoicePaymentResponse,
    ) -> None:
        """Persist the one-time charge result — best-effort, NEVER raises.

        Runs AFTER a successful charge, so it must never propagate: a
        post-charge exception here would unwind into the start op's blanket
        ``except`` and DELETE the just-charged rows — un-billing a successful
        charge, which is forbidden. Every write therefore runs under its own
        guard (logged on failure, then skipped), mirroring the recurring
        ``PaymentSyncWriteback`` swallow-and-log policy. A row that does not get
        stamped stays un-``applied``; the caller's verify then marks it
        failed-but-KEPT (its invoice line is billed and is never un-billed) and
        the reconciler / next sync heals the Stripe-confirmation stamp.

        Maps each membership 1:1 to its invoice line by order (``plan.items[i]``
        ↔ ``result.line_item_ids[i]`` / ``line_amounts[i]``): stamps the line id +
        invoice id + post-discount ``total_price`` + ``applied`` on each row, then
        reuses the recurring coupon-link writeback (the resolved coupon onto each
        contributing applied-discount row). A one-time membership is terminal
        (one invoice), so there is no consumption stamp.
        """
        await self._writeback_membership_rows(plan, result)
        await self._writeback_coupon_links(plan)

    async def _writeback_membership_rows(
        self,
        plan: OneTimeInvoicePlan,
        result: PaymentsInvoicePaymentResponse,
    ) -> None:
        """Stamp each membership row from its invoice line — guarded per row.

        Pairs ``plan.items`` with the returned line id + amount by order. A
        line-count mismatch (Stripe billed a different number of lines than we
        sent) is logged loud and the overlap still stamped best-effort — never
        raised, because the charge already happened (a raise here would route
        the start op to its delete branch and un-bill a real charge). Each row
        is stamped under its own guard so one bad row never blocks the rest.
        """
        if (
            len(result.line_item_ids) != len(plan.items)
            or len(result.line_amounts) != len(plan.items)
        ):
            logger.error(
                "One-time writeback: Stripe returned %d line ids / %d amounts "
                "for %d membership items on invoice %s; stamping the overlap "
                "best-effort (charge already happened, never un-billing)",
                len(result.line_item_ids),
                len(result.line_amounts),
                len(plan.items),
                result.stripe_invoice_id,
            )
        for item, line_id, amount in zip(
            plan.items,
            result.line_item_ids,
            result.line_amounts,
            strict=False,  # mismatch already logged above; stamp the overlap
        ):
            try:
                await self._queries.apply_one_time_membership_sync(
                    item_id=item.item_id,
                    member_id=item.member_id,
                    stripe_item_id=line_id,
                    stripe_one_time_invoice_id=result.stripe_invoice_id,
                    total_price=amount,
                )
            except Exception:
                logger.error(
                    "One-time writeback: failed to stamp membership row "
                    "item_id=%s member_id=%s; continuing",
                    item.item_id,
                    item.member_id,
                    exc_info=True,
                )

    async def _writeback_coupon_links(
        self,
        plan: OneTimeInvoicePlan,
    ) -> None:
        """Link each resolved coupon onto its applied-discount row — guarded.

        Mirrors the recurring ``PaymentSyncWriteback`` coupon-link writeback:
        one bad row is logged and skipped so the others still land, and nothing
        here raises (the charge is already done).
        """
        for applied_discount_id, coupon_id in plan.coupon_links.items():
            try:
                await self._queries.set_applied_discount_coupon_id(
                    applied_discount_id,
                    coupon_id,
                )
            except Exception:
                logger.error(
                    "One-time writeback: failed to link coupon %s onto applied "
                    "discount %s; continuing",
                    coupon_id,
                    applied_discount_id,
                    exc_info=True,
                )
