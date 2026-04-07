import logging

from stripe.params._subscription_update_params import (
    SubscriptionUpdateParams,
    SubscriptionUpdateParamsItem,
)

from src.payments.payments_exceptions import (
    PaymentsResourceNotFoundError,
)
from src.payments.schema.payments_enums import StripeResourceType
from src.payments.schema.payments_members_schema import (
    PaymentsResourceNotFoundDetail,
    PaymentsSubscriptionPriceMigrationError,
    PaymentsSubscriptionPriceMigrationRequest,
    PaymentsSubscriptionPriceMigrationResponse,
)
from src.payments.service.subscription.payments_subscription_base import (
    PaymentsSubscriptionBase,
)

logger = logging.getLogger(__name__)


class PaymentsSubscriptionMigration(PaymentsSubscriptionBase):
    """Batch migrate subscriptions between prices."""

    async def migrate_subscriptions_to_price(
        self,
        request: PaymentsSubscriptionPriceMigrationRequest,
        stripe_account_id: str,
    ) -> PaymentsSubscriptionPriceMigrationResponse:
        """Migrate subscriptions to a new price sequentially.

        Finds the item matching ``old_stripe_price_id`` and updates
        it to the new price. Processes one at a time to stay within
        Stripe's rate limits.

        Args:
            request: Subscription IDs, old/new price IDs, proration behavior.
            stripe_account_id: The gym's Stripe Connect account ID.

        Returns:
            Lists of migrated IDs and errors.
        """
        opts = self._client.connect_opts(stripe_account_id)

        await self._prices.validate_price_active(
            request.new_stripe_price_id,
            stripe_account_id,
        )

        migrated: list[str] = []
        errors: list[PaymentsSubscriptionPriceMigrationError] = []

        for sub_id in request.subscription_ids:
            try:
                sub = await self._retrieve_subscription(sub_id, opts)
            except PaymentsResourceNotFoundError:
                errors.append(
                    PaymentsSubscriptionPriceMigrationError(
                        subscription_id=sub_id,
                        stripe_account_id=stripe_account_id,
                        not_found=PaymentsResourceNotFoundDetail(
                            resource_id=sub_id,
                            resource_type=StripeResourceType.subscription,
                        ),
                    )
                )
                continue

            try:
                if not sub.items or not sub.items.data:
                    errors.append(
                        PaymentsSubscriptionPriceMigrationError(
                            subscription_id=sub_id,
                            stripe_account_id=stripe_account_id,
                            not_found=PaymentsResourceNotFoundDetail(
                                resource_id=sub_id,
                                resource_type=StripeResourceType.subscription_item,
                            ),
                        )
                    )
                    continue

                target_item = next(
                    (
                        item
                        for item in sub.items.data
                        if item.price.id == request.old_stripe_price_id
                    ),
                    None,
                )
                if target_item is None:
                    errors.append(
                        PaymentsSubscriptionPriceMigrationError(
                            subscription_id=sub_id,
                            stripe_account_id=stripe_account_id,
                            not_found=PaymentsResourceNotFoundDetail(
                                resource_id=request.old_stripe_price_id,
                                resource_type=StripeResourceType.price,
                            ),
                        )
                    )
                    continue

                await self._stripe.v1.subscriptions.update_async(
                    sub_id,
                    params=SubscriptionUpdateParams(
                        items=[
                            SubscriptionUpdateParamsItem(
                                id=target_item.id,
                                price=request.new_stripe_price_id,
                            ),
                        ],
                        proration_behavior=request.proration_behavior,
                    ),
                    options=opts,
                )
                migrated.append(sub_id)
            except Exception as exc:
                logger.warning(
                    "Failed to migrate subscription %s to price %s",
                    sub_id,
                    request.new_stripe_price_id,
                    exc_info=True,
                )
                errors.append(
                    PaymentsSubscriptionPriceMigrationError(
                        subscription_id=sub_id,
                        stripe_account_id=stripe_account_id,
                        stripe_error=str(exc),
                    )
                )

        return PaymentsSubscriptionPriceMigrationResponse(
            migrated=migrated,
            errors=errors,
        )
