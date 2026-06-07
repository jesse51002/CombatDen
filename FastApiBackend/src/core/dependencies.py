from dependency_injector import containers, providers

from src.classes.service.checkin.classes_checkin_service import (
    ClassesCheckinService,
)
from src.classes.service.classes_cycle_counts_service import (
    ClassesCycleCountsService,
)
from src.classes.service.classes_streak_service import ClassesStreakService
from src.core.config import settings
from src.discounts.service.discounts.discounts_service import DiscountsService
from src.gyms.service.gyms_service import GymsService
from src.gyms.service.gyms_stripe_connect_service import (
    GymsStripeConnectService,
)
from src.member_memberships.service.memberships.member_memberships_service import (
    MemberMembershipsService,
)
from src.member_memberships.service.payment_sync.payment_sync_builder import (
    PaymentSyncBuilder,
)
from src.member_memberships.service.payment_sync.payment_sync_discounts import (
    PaymentSyncDiscounts,
)
from src.member_memberships.service.payment_sync.payment_sync_freeze import (
    PaymentSyncFreeze,
)
from src.member_memberships.service.payment_sync.payment_sync_once_discounts import (
    PaymentSyncOnceDiscounts,
)
from src.member_memberships.service.payment_sync.payment_sync_service import (
    PaymentSyncService,
)
from src.members.service.crm_member_services.members_crm_members_list_service import (
    CrmMembersListService,
)
from src.members.service.crm_member_services.members_crm_total_counts_service import (
    CrmTotalCountsService,
)
from src.members.service.management.members_management_service import (
    MembersManagementService,
)
from src.members.service.member_details.members_billing_detail_service import (
    MembersBillingDetailService,
)
from src.members.service.member_payments_service import (
    MembersPaymentsService,
)
from src.membership_plans.service.plans.membership_plans_service import (
    MembershipPlansService,
)
from src.payments.service.payments_stripe_client import PaymentsStripeClient
from src.payments.service.payments_stripe_discount_service import (
    PaymentsStripeDiscountService,
)
from src.payments.service.payments_stripe_members_service import (
    PaymentsStripeMembersService,
)
from src.payments.service.payments_stripe_membership_service import (
    PaymentsStripeMembershipService,
)
from src.payments.service.payments_stripe_payment_service import (
    PaymentsStripePaymentService,
)
from src.payments.service.payments_stripe_price_service import (
    PaymentsStripePriceService,
)
from src.payments.service.subscription import (
    PaymentsStripeSubscriptionService,
)
from src.ranks.service.ranks_service import RanksService
from src.rewards.service.rewards_redemption_service import (
    RewardsRedemptionService,
)
from src.rewards.service.rewards_service import RewardsService
from src.shared.auth import Auth
from src.shared.billing_parent_resolver import BillingParentResolver
from src.shared.database import DirectDatabasePool, SupabaseClient
from src.shared.gym_stripe_service import GymStripeService
from src.shared.paying_member_lock import PayingMemberLock
from src.stripe_webhooks.service.account_updated_handler import (
    AccountUpdatedHandler,
)
from src.stripe_webhooks.service.event_log import StripeWebhookEventLog
from src.stripe_webhooks.service.invoice_paid_handler import (
    InvoicePaidHandler,
)
from src.stripe_webhooks.service.invoice_payment_failed_handler import (
    InvoicePaymentFailedHandler,
)
from src.stripe_webhooks.service.invoice_payment_paid_handler import (
    InvoicePaymentPaidHandler,
)
from src.stripe_webhooks.service.refund_handler import (
    RefundHandler,
)
from src.stripe_webhooks.service.stripe_webhooks_service import (
    StripeWebhooksService,
)
from src.waivers.service.waivers.waivers_service import WaiversService


class DependencyInjector(containers.DeclarativeContainer):
    """Application dependency injection container.

    Add new domain modules to wiring_config.modules
    when they use @inject with Provide[...].
    """

    wiring_config = containers.WiringConfiguration(
        modules=[
            "src.main",
            "src.classes.classes_router",
            "src.gyms.gyms_router",
            "src.members.members_router",
            "src.ranks.ranks_router",
            "src.rewards.rewards_router",
            "src.waivers.waivers_router",
            # === CRM billing router modules (restored) ===
            "src.discounts.discounts_router",
            "src.member_memberships.member_memberships_router",
            "src.membership_plans.membership_plans_router",
            "src.stripe_webhooks.stripe_webhooks_router",
            # === end CRM billing router modules ===
        ],
    )

    db_pool = providers.Singleton(DirectDatabasePool)
    supabase = providers.Singleton(SupabaseClient)
    auth = providers.Singleton(Auth, supabase=supabase)

    streak_service = providers.Factory(ClassesStreakService, db_pool=db_pool)
    cycle_counts_service = providers.Factory(
        ClassesCycleCountsService,
        db_pool=db_pool,
    )
    checkin_service = providers.Factory(
        ClassesCheckinService,
        db_pool=db_pool,
        cycle_counts_service=cycle_counts_service,
    )

    rewards_service = providers.Factory(RewardsService, db_pool=db_pool)
    rewards_redemption_service = providers.Factory(RewardsRedemptionService, db_pool=db_pool)

    ranks_service = providers.Factory(RanksService, db_pool=db_pool)

    # Waivers: plain gym config (versioned documents + read-only e-sign
    # tracking), no Stripe.
    waivers_service = providers.Factory(WaiversService, db_pool=db_pool)

    # === CRM billing DI providers (restored) ===
    # Shared Stripe infrastructure (per-gym connected-account lookups).
    gym_stripe_service = providers.Factory(GymStripeService, db_pool=db_pool)

    # ── Payments (Stripe service core) ───────────────────────────
    stripe_client = providers.Singleton(
        PaymentsStripeClient,
        secret_key=settings.stripe_secret_key,
    )
    payments_price_service = providers.Factory(
        PaymentsStripePriceService,
        stripe_client=stripe_client,
    )
    payments_discount_service = providers.Factory(
        PaymentsStripeDiscountService,
        stripe_client=stripe_client,
    )
    payments_members_service = providers.Factory(
        PaymentsStripeMembersService,
        stripe_client=stripe_client,
    )
    payments_membership_service = providers.Factory(
        PaymentsStripeMembershipService,
        stripe_client=stripe_client,
        price_service=payments_price_service,
    )
    payments_payment_service = providers.Factory(
        PaymentsStripePaymentService,
        stripe_client=stripe_client,
        members_service=payments_members_service,
        price_service=payments_price_service,
    )
    payments_subscription_service = providers.Factory(
        PaymentsStripeSubscriptionService,
        stripe_client=stripe_client,
        members_service=payments_members_service,
        price_service=payments_price_service,
        discount_service=payments_discount_service,
    )

    # ── Payment sync ─────────────────────────────────────────────
    # Shared parent/billing-account resolver, injected wherever parent
    # resolution is needed: the sync, the freeze service, and the lifecycle /
    # validation callers (start, freeze, charge_card, mark_paid_cash).
    billing_parent_resolver = providers.Factory(
        BillingParentResolver,
        db_pool=db_pool,
        gym_stripe_service=gym_stripe_service,
    )
    # The one concurrency lock: a TTL lease keyed on a member's paying parent,
    # so no two billing ops sync the same family at once. Used by the facade,
    # the webhook settle, and the bulk fan-out.
    paying_member_lock = providers.Factory(
        PayingMemberLock,
        db_pool=db_pool,
        parent_resolver=billing_parent_resolver,
    )
    # Standalone freeze service: the dedicated freeze/unfreeze request resolves
    # the parent then calls this directly; the sync uses it for the maintenance
    # re-apply with the parent it already resolved.
    payment_sync_freeze = providers.Factory(
        PaymentSyncFreeze,
        subscription_service=payments_subscription_service,
    )
    # Pre-sync settle of the once-discount lifecycle (stamps consumed `once`
    # snapshots); also the scheduled reconciler's core duty.
    payment_sync_once_discounts = providers.Factory(
        PaymentSyncOnceDiscounts,
        db_pool=db_pool,
        subscription_service=payments_subscription_service,
    )
    # Owns the discount math + resolves each line's coupons (find-or-create,
    # dollar→percent), for both real and preview. Coupon I/O is delegated to the
    # payments discount service — the sync never touches the Stripe SDK directly.
    payment_sync_discounts = providers.Factory(
        PaymentSyncDiscounts,
        discount_service=payments_discount_service,
    )
    # Builds the desired SyncParams from the DB: read memberships + discounts,
    # group by price, resolve coupons, assemble the bucket.
    payment_sync_builder = providers.Factory(
        PaymentSyncBuilder,
        db_pool=db_pool,
        discounts=payment_sync_discounts,
    )
    payment_sync_service = providers.Factory(
        PaymentSyncService,
        db_pool=db_pool,
        subscription_service=payments_subscription_service,
        parent_resolver=billing_parent_resolver,
        freeze=payment_sync_freeze,
        once_discounts=payment_sync_once_discounts,
        builder=payment_sync_builder,
        paying_lock=paying_member_lock,
    )

    # ── Member memberships ───────────────────────────────────────
    member_memberships_service = providers.Factory(
        MemberMembershipsService,
        db_pool=db_pool,
        payment_sync_service=payment_sync_service,
        payment_service=payments_payment_service,
        gym_stripe_service=gym_stripe_service,
        parent_resolver=billing_parent_resolver,
        freeze_service=payment_sync_freeze,
        paying_lock=paying_member_lock,
    )

    # ── Members CRM list / counts (OG, membership-derived) ───────
    crm_members_list_service = providers.Factory(
        CrmMembersListService,
        db_pool=db_pool,
    )
    crm_total_counts_service = providers.Factory(
        CrmTotalCountsService,
        db_pool=db_pool,
    )

    # ── Members billing/management ───────────────────────────────
    members_billing_detail_service = providers.Factory(
        MembersBillingDetailService,
        db_pool=db_pool,
        streak_service=streak_service,
        cycle_counts_service=cycle_counts_service,
    )
    members_payments_service = providers.Factory(
        MembersPaymentsService,
        db_pool=db_pool,
    )
    members_management_service = providers.Factory(
        MembersManagementService,
        db_pool=db_pool,
        payments_members_service=payments_members_service,
        subscription_service=payments_subscription_service,
    )

    # ── Discounts ────────────────────────────────────────────────
    # Presets are plain, coupon-free gym config: no Stripe, no payment sync.
    discounts_service = providers.Factory(
        DiscountsService,
        db_pool=db_pool,
    )

    # ── Membership plans ─────────────────────────────────────────
    membership_plans_service = providers.Factory(
        MembershipPlansService,
        db_pool=db_pool,
        gym_stripe_service=gym_stripe_service,
        stripe_membership_service=payments_membership_service,
        stripe_price_service=payments_price_service,
        payment_sync_service=payment_sync_service,
        discounts_service=discounts_service,
    )

    # ── Gyms (Stripe Express onboarding) ─────────────────────────
    gyms_stripe_connect_service = providers.Factory(
        GymsStripeConnectService,
        stripe_client=stripe_client,
    )
    gyms_service = providers.Factory(
        GymsService,
        db_pool=db_pool,
        stripe_connect_service=gyms_stripe_connect_service,
    )

    # ── Stripe webhooks ──────────────────────────────────────────
    stripe_webhook_event_log = providers.Factory(StripeWebhookEventLog)
    stripe_webhook_invoice_paid_handler = providers.Factory(
        InvoicePaidHandler,
        payment_sync_service=payment_sync_service,
        paying_lock=paying_member_lock,
        stripe_client=stripe_client,
    )
    stripe_webhook_invoice_payment_paid_handler = providers.Factory(
        InvoicePaymentPaidHandler,
        stripe_client=stripe_client,
    )
    stripe_webhook_invoice_payment_failed_handler = providers.Factory(
        InvoicePaymentFailedHandler,
    )
    stripe_webhook_refund_handler = providers.Factory(
        RefundHandler,
    )
    stripe_webhook_account_updated_handler = providers.Factory(
        AccountUpdatedHandler,
    )
    stripe_webhooks_service = providers.Factory(
        StripeWebhooksService,
        db_pool=db_pool,
        event_log=stripe_webhook_event_log,
        invoice_paid_handler=stripe_webhook_invoice_paid_handler,
        invoice_payment_paid_handler=stripe_webhook_invoice_payment_paid_handler,
        invoice_payment_failed_handler=stripe_webhook_invoice_payment_failed_handler,
        refund_handler=stripe_webhook_refund_handler,
        account_updated_handler=stripe_webhook_account_updated_handler,
    )
    # === end CRM billing DI providers ===
