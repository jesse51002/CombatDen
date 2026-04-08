from src.payments.schema.payments_invoice_schema import (
    PaymentsInvoicePreviewResponse,
)
from src.payments.schema.payments_members_schema import (
    PaymentsSubscriptionCancelRequest,
    PaymentsSubscriptionCreateRequest,
    PaymentsSubscriptionFreezeRequest,
    PaymentsSubscriptionFreezeResponse,
    PaymentsSubscriptionItemResponse,
    PaymentsSubscriptionPriceMigrationRequest,
    PaymentsSubscriptionPriceMigrationResponse,
    PaymentsSubscriptionResponse,
    PaymentsSubscriptionUnfreezeRequest,
    PaymentsSubscriptionUpdateRequest,
)
from src.payments.service.payments_stripe_client import (
    PaymentsStripeClient,
)
from src.payments.service.payments_stripe_discount_service import (
    PaymentsStripeDiscountService,
)
from src.payments.service.payments_stripe_members_service import (
    PaymentsStripeMembersService,
)
from src.payments.service.payments_stripe_price_service import (
    PaymentsStripePriceService,
)
from src.payments.service.subscription.payments_subscription_cancel import (
    PaymentsSubscriptionCancel,
)
from src.payments.service.subscription.payments_subscription_create import (
    PaymentsSubscriptionCreate,
)
from src.payments.service.subscription.payments_subscription_freeze import (
    PaymentsSubscriptionFreeze,
)
from src.payments.service.subscription.payments_subscription_item import (
    PaymentsSubscriptionItem,
)
from src.payments.service.subscription.payments_subscription_migration import (
    PaymentsSubscriptionMigration,
)
from src.payments.service.subscription.payments_subscription_update import (
    PaymentsSubscriptionUpdate,
)


class PaymentsStripeSubscriptionService:
    """Stripe Subscription operations (facade).

    Delegates to focused sub-services while preserving
    the original public API and constructor signature.
    Uses flexible billing mode and the ``discounts`` array.
    All methods accept ``stripe_account_id`` for Stripe Connect.
    """

    def __init__(
        self,
        stripe_client: PaymentsStripeClient,
        members_service: PaymentsStripeMembersService,
        price_service: PaymentsStripePriceService,
        discount_service: PaymentsStripeDiscountService,
    ) -> None:
        deps = (
            stripe_client,
            members_service,
            price_service,
            discount_service,
        )
        self._create = PaymentsSubscriptionCreate(*deps)
        self._update = PaymentsSubscriptionUpdate(*deps)
        self._cancel = PaymentsSubscriptionCancel(*deps)
        self._freeze = PaymentsSubscriptionFreeze(*deps)
        self._migration = PaymentsSubscriptionMigration(*deps)
        self._item = PaymentsSubscriptionItem(*deps)

    # ── Create ────────────────────────────────────────────────────

    async def create_subscription(
        self,
        request: PaymentsSubscriptionCreateRequest,
        stripe_account_id: str,
    ) -> PaymentsSubscriptionResponse:
        """Create a new subscription with flexible billing mode."""
        return await self._create.create_subscription(request, stripe_account_id)

    async def preview_create_subscription(
        self,
        request: PaymentsSubscriptionCreateRequest,
        stripe_account_id: str,
    ) -> PaymentsInvoicePreviewResponse:
        """Preview the first invoice for a new subscription."""
        return await self._create.preview_create_subscription(request, stripe_account_id)

    # ── Update ────────────────────────────────────────────────────

    async def update_subscription(
        self,
        request: PaymentsSubscriptionUpdateRequest,
        stripe_account_id: str,
    ) -> PaymentsSubscriptionResponse:
        """Update an existing subscription to match the desired state."""
        return await self._update.update_subscription(request, stripe_account_id)

    async def preview_update_subscription(
        self,
        request: PaymentsSubscriptionUpdateRequest,
        stripe_account_id: str,
    ) -> PaymentsInvoicePreviewResponse:
        """Preview the next invoice after updating a subscription."""
        return await self._update.preview_update_subscription(request, stripe_account_id)

    # ── Subscription-Level Operations ─────────────────────────────

    async def cancel_subscription(
        self,
        request: PaymentsSubscriptionCancelRequest,
        stripe_account_id: str,
    ) -> PaymentsSubscriptionResponse:
        """Cancel a subscription immediately or at period end."""
        return await self._cancel.cancel_subscription(request, stripe_account_id)

    async def freeze_subscription(
        self,
        request: PaymentsSubscriptionFreezeRequest,
        stripe_account_id: str,
    ) -> PaymentsSubscriptionFreezeResponse:
        """Pause collection on a subscription (freeze)."""
        return await self._freeze.freeze_subscription(request, stripe_account_id)

    async def unfreeze_subscription(
        self,
        request: PaymentsSubscriptionUnfreezeRequest,
        stripe_account_id: str,
    ) -> PaymentsSubscriptionResponse:
        """Resume collection on a paused subscription (unfreeze)."""
        return await self._freeze.unfreeze_subscription(request, stripe_account_id)

    # ── Item ─────────────────────────────────────────────────────

    async def get_subscription_item(
        self,
        subscription_item_id: str,
        stripe_account_id: str,
    ) -> PaymentsSubscriptionItemResponse:
        """Retrieve a single subscription item."""
        return await self._item.get_item(subscription_item_id, stripe_account_id)

    # ── Batch Migration ───────────────────────────────────────────

    async def migrate_subscriptions_to_price(
        self,
        request: PaymentsSubscriptionPriceMigrationRequest,
        stripe_account_id: str,
    ) -> PaymentsSubscriptionPriceMigrationResponse:
        """Migrate subscriptions to a new price sequentially."""
        return await self._migration.migrate_subscriptions_to_price(request, stripe_account_id)
