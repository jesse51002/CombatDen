import logging
from datetime import UTC, date, datetime, timedelta
from typing import Any

import stripe

import src.shared.db_schema_path  # noqa: F401
from src.payments.payments_exceptions import PaymentsResourceNotFoundError
from src.payments.schema.payments_enums import StripeResourceType
from src.payments.schema.payments_members_schema import (
    PaymentsSubscriptionCreateRequest,
    PaymentsSubscriptionDesiredItem,
    PaymentsSubscriptionItemResponse,
    PaymentsSubscriptionResponse,
    SubscriptionItemDiscount,
)
from src.payments.service.payments_stripe_client import PaymentsStripeClient
from src.payments.service.payments_stripe_discount_service import (
    PaymentsStripeDiscountService,
)
from src.payments.service.payments_stripe_members_service import (
    PaymentsStripeMembersService,
)
from src.payments.service.payments_stripe_price_service import (
    PaymentsStripePriceService,
)

logger = logging.getLogger(__name__)


class PaymentsSubscriptionBase:
    """Base class for subscription operations.

    Holds shared dependencies and helper methods used across
    all subscription sub-services.
    """

    def __init__(
        self,
        stripe_client: PaymentsStripeClient,
        members_service: PaymentsStripeMembersService,
        price_service: PaymentsStripePriceService,
        discount_service: PaymentsStripeDiscountService,
    ) -> None:
        self._client = stripe_client
        self._stripe = stripe_client.client
        self._members = members_service
        self._prices = price_service
        self._discounts = discount_service

    # ── Static Helpers ────────────────────────────────────────────

    @staticmethod
    def _date_to_unix(d: date) -> int:
        """Convert a date to a UTC unix timestamp (midnight)."""
        return int(datetime(d.year, d.month, d.day, tzinfo=UTC).timestamp())

    @staticmethod
    def _next_weekday_timestamp(target_weekday: int) -> int:
        """Compute UTC midnight timestamp for the next occurrence of target_weekday.

        Args:
            target_weekday: Python weekday (0=Monday, 6=Sunday).

        Returns:
            UTC unix timestamp at midnight on the next target_weekday.
        """
        today = datetime.now(UTC).date()
        days_ahead = target_weekday - today.weekday()
        if days_ahead <= 0:
            days_ahead += 7
        next_day = today + timedelta(days=days_ahead)
        return int(datetime(next_day.year, next_day.month, next_day.day, tzinfo=UTC).timestamp())

    @staticmethod
    def _map_subscription(
        sub: stripe.Subscription,
    ) -> PaymentsSubscriptionResponse:
        """Map a Stripe Subscription to our response schema."""
        items: list[PaymentsSubscriptionItemResponse] = []
        if sub.items and sub.items.data:
            for si in sub.items.data:
                item_discount_ids: list[str] = []
                if hasattr(si, "discounts") and si.discounts:
                    for d in si.discounts:
                        if hasattr(d, "coupon") and d.coupon:
                            item_discount_ids.append(d.coupon.id)
                items.append(
                    PaymentsSubscriptionItemResponse(
                        stripe_subscription_item_id=si.id,
                        stripe_price_id=si.price.id,
                        quantity=si.quantity or 1,
                        discounts=item_discount_ids,
                    )
                )

        sub_discount_ids: list[str] = []
        if sub.discounts:
            for d in sub.discounts:
                if hasattr(d, "coupon") and d.coupon:
                    sub_discount_ids.append(d.coupon.id)

        return PaymentsSubscriptionResponse(
            stripe_subscription_id=sub.id,
            stripe_customer_id=sub.customer,
            items=items,
            status=sub.status,
            current_period_start=sub.current_period_start,
            current_period_end=sub.current_period_end,
            cancel_at_period_end=sub.cancel_at_period_end,
            discounts=sub_discount_ids,
            metadata=dict(sub.metadata) if sub.metadata else {},
        )

    # ── Item Builders ─────────────────────────────────────────────

    @staticmethod
    def _build_create_items(
        consolidated_items: list[PaymentsSubscriptionDesiredItem],
    ) -> list[dict[str, Any]]:
        """Build item dicts for a new subscription (create or preview).

        Returns:
            List of item dicts with price, quantity, and optional discounts.
        """
        items: list[dict[str, Any]] = []
        for item in consolidated_items:
            entry: dict[str, Any] = {
                "price": item.stripe_price_id,
                "quantity": item.quantity,
            }
            if item.discounts:
                entry["discounts"] = [{"coupon": d.coupon} for d in item.discounts]
            items.append(entry)
        return items

    @staticmethod
    def _build_reconcile_items(
        consolidated_items: list[PaymentsSubscriptionDesiredItem],
        sub: stripe.Subscription,
    ) -> list[dict[str, Any]]:
        """Build item dicts for a subscription update (reconcile or preview).

        Diffs desired items against current subscription items.
        Items with ``id`` are updates, without ``id`` are adds,
        and items with ``deleted=True`` are removals.

        Returns:
            List of item dicts ready for subscription update or preview.
        """
        current_by_price: dict[str, Any] = {}
        if sub.items and sub.items.data:
            for si in sub.items.data:
                current_by_price[si.price.id] = si

        desired_prices = {item.stripe_price_id for item in consolidated_items}

        items: list[dict[str, Any]] = []
        for item in consolidated_items:
            if item.stripe_price_id in current_by_price:
                si = current_by_price[item.stripe_price_id]
                entry: dict[str, Any] = {
                    "id": si.id,
                    "price": item.stripe_price_id,
                    "quantity": item.quantity,
                    "discounts": (
                        [{"coupon": d.coupon} for d in item.discounts] if item.discounts else ""
                    ),
                }
            else:
                entry = {
                    "price": item.stripe_price_id,
                    "quantity": item.quantity,
                }
                if item.discounts:
                    entry["discounts"] = [{"coupon": d.coupon} for d in item.discounts]
            items.append(entry)

        for price_id, si in current_by_price.items():
            if price_id not in desired_prices:
                items.append({"id": si.id, "deleted": True})

        return items

    @staticmethod
    def _build_subscription_discounts(
        discounts: list[SubscriptionItemDiscount],
    ) -> list[dict[str, str]] | str:
        """Build subscription-level discount params.

        Returns a list of coupon dicts, or empty string to clear.
        """
        if discounts:
            return [{"coupon": d.coupon} for d in discounts]
        return ""

    # ── Item Consolidation ────────────────────────────────────────

    @staticmethod
    def _consolidate_items(
        items: list[PaymentsSubscriptionDesiredItem],
    ) -> list[PaymentsSubscriptionDesiredItem]:
        """Merge items that share the same price ID.

        Stripe only allows one subscription item per price. When the
        caller sends duplicates this method sums their quantities and
        deduplicates their coupon IDs.

        Args:
            items: Desired items (may contain duplicate price IDs).

        Returns:
            Consolidated list with unique price IDs.
        """
        groups: dict[str, list[PaymentsSubscriptionDesiredItem]] = {}
        for item in items:
            groups.setdefault(item.stripe_price_id, []).append(item)

        consolidated: list[PaymentsSubscriptionDesiredItem] = []
        for price_id, group in groups.items():
            if len(group) == 1:
                consolidated.append(group[0])
                continue

            total_quantity = sum(it.quantity for it in group)

            seen: set[str] = set()
            unique_discounts: list[SubscriptionItemDiscount] = []
            for it in group:
                for d in it.discounts:
                    if d.coupon not in seen:
                        seen.add(d.coupon)
                        unique_discounts.append(d)

            consolidated.append(
                PaymentsSubscriptionDesiredItem(
                    stripe_price_id=price_id,
                    quantity=total_quantity,
                    discounts=unique_discounts,
                )
            )

        return consolidated

    # ── Instance Helpers ──────────────────────────────────────────

    async def _retrieve_subscription(
        self,
        subscription_id: str,
        opts: stripe.RequestOptions,
    ) -> stripe.Subscription:
        """Retrieve a Stripe Subscription, raising if not found."""
        try:
            return await self._stripe.v1.subscriptions.retrieve_async(
                subscription_id,
                options=opts,
            )
        except stripe.InvalidRequestError as exc:
            raise PaymentsResourceNotFoundError(
                f"Subscription {subscription_id} not found",
                resource_id=subscription_id,
                resource_type=StripeResourceType.subscription,
            ) from exc

    async def _validate_coupon_ids(
        self,
        coupon_ids: list[str],
        opts: stripe.RequestOptions,
    ) -> None:
        """Pre-validate that all coupon IDs exist and are not deleted."""
        for coupon_id in coupon_ids:
            await self._discounts.retrieve_discount(coupon_id, opts)

    async def _validate_subscription_request(
        self,
        request: PaymentsSubscriptionCreateRequest,
        stripe_account_id: str,
    ) -> str | None:
        """Validate all prices and coupons in the request.

        Returns the recurring interval shared by all items.
        """
        opts = self._client.connect_opts(stripe_account_id)

        interval: str | None = None
        for item in request.items:
            price = await self._prices.validate_price_active(
                item.stripe_price_id,
                stripe_account_id,
            )
            if price.recurring_interval is None:
                raise ValueError("Price must be recurring for subscription.")

            if interval is None:
                interval = price.recurring_interval
            elif interval != price.recurring_interval:
                raise ValueError(
                    "All recurring intervals must be the same."
                    f"{interval} and {price.recurring_interval}"
                )

        all_coupon_ids: list[str] = []
        for item in request.items:
            all_coupon_ids.extend(d.coupon for d in item.discounts)
        all_coupon_ids.extend(d.coupon for d in request.subscription_discounts)
        if all_coupon_ids:
            await self._validate_coupon_ids(all_coupon_ids, opts)

        return interval
