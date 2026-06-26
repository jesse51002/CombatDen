"""Charge a payer's PENDING one-time memberships on one consolidated invoice."""

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
    """Charge a payer's pending one-time memberships on a single invoice."""

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
        """Charge the payer's PENDING one-time memberships; no-op when none pending."""
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

        Strips subscription lines from the Stripe preview so only ad-hoc
        one-time lines remain; returns None when nothing is staged.
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
        """Drop subscription/proration lines from a customer preview; recompute totals."""
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
        """Build the one-time invoice plan: one line per pending membership."""
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
        """One singleton group per membership so resolve's ÷quantity is a no-op."""
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
        """Distinct membership owners across all invoice lines, in order."""
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
        """Create and charge the invoice on the payer's Stripe customer."""
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
        """Persist the charge result — best-effort, never raises (charge already happened)."""
        await self._writeback_membership_rows(plan, result)
        await self._writeback_coupon_links(plan)

    async def _writeback_membership_rows(
        self,
        plan: OneTimeInvoicePlan,
        result: PaymentsInvoicePaymentResponse,
    ) -> None:
        """Stamp line id + amount onto each membership row; guarded per row."""
        if (
            len(result.line_item_ids) != len(plan.items)
            or len(result.line_amounts) != len(plan.items)
        ):
            logger.error(
                "One-time writeback: line count mismatch (%d ids / %d amounts "
                "for %d items) on invoice %s; stamping overlap best-effort",
                len(result.line_item_ids),
                len(result.line_amounts),
                len(plan.items),
                result.stripe_invoice_id,
            )
        for item, line_id, amount in zip(
            plan.items,
            result.line_item_ids,
            result.line_amounts,
            strict=False,  # mismatch logged above; stamp the overlap
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
        """Write coupon id onto each applied-discount row; guarded per row."""
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
