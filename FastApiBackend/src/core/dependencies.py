from dependency_injector import containers, providers

from src.classes.service.classes_checkin_service import ClassesCheckinService
from src.classes.service.classes_cycle_counts_service import (
    ClassesCycleCountsService,
)
from src.classes.service.classes_streak_service import ClassesStreakService
from src.core.config import settings
from src.discounts.service.discounts_service import DiscountsService
from src.member_memberships.service.linked_member_discount_service import (
    LinkedMemberDiscountService,
)
from src.member_memberships.service.member_memberships_service import (
    MemberMembershipsService,
)
from src.member_memberships.service.membership_payment_sync_service import (
    MembershipPaymentSyncService,
)
from src.members.service.member_details_service import (
    MemberService,
)
from src.members.service.members_crm_members_list_service import (
    CrmMembersListService,
)
from src.members.service.members_crm_total_counts_service import (
    CrmTotalCountsService,
)
from src.members.service.members_management_service import (
    MembersManagementService,
)
from src.membership_plans.service.membership_plans_service import (
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
from src.shared.auth import Auth
from src.shared.database import (
    DirectDatabasePool,
    SupabaseClient,
)
from src.shared.gym_stripe_service import GymStripeService
from src.stripe_webhooks.service.event_log import StripeWebhookEventLog
from src.stripe_webhooks.service.handlers.charge_refunded_handler import (
    ChargeRefundedHandler,
)
from src.stripe_webhooks.service.handlers.invoice_paid_handler import (
    InvoicePaidHandler,
)
from src.stripe_webhooks.service.handlers.invoice_payment_failed_handler import (
    InvoicePaymentFailedHandler,
)
from src.stripe_webhooks.service.stripe_webhooks_service import (
    StripeWebhooksService,
)


class DependencyInjector(containers.DeclarativeContainer):
    """Application dependency injection container.

    Add new domain modules to wiring_config.modules
    when they use @inject with Provide[...].
    """

    wiring_config = containers.WiringConfiguration(
        modules=[
            "src.main",
            "src.members.members_router",
            "src.member_memberships.member_memberships_router",
            "src.classes.classes_router",
            "src.discounts.discounts_router",
            "src.membership_plans.membership_plans_router",
            "src.stripe_webhooks.stripe_webhooks_router",
        ],
    )

    db_pool = providers.Singleton(DirectDatabasePool)
    supabase = providers.Singleton(SupabaseClient)
    auth = providers.Singleton(Auth, supabase=supabase)
    cycle_counts_service = providers.Factory(ClassesCycleCountsService, db_pool=db_pool)
    streak_service = providers.Factory(ClassesStreakService, db_pool=db_pool)
    member_service = providers.Factory(
        MemberService,
        db_pool=db_pool,
        cycle_counts_service=cycle_counts_service,
        streak_service=streak_service,
    )
    crm_members_list_service = providers.Factory(CrmMembersListService, db_pool=db_pool)
    crm_total_counts_service = providers.Factory(CrmTotalCountsService, db_pool=db_pool)
    checkin_service = providers.Factory(
        ClassesCheckinService,
        db_pool=db_pool,
        cycle_counts_service=cycle_counts_service,
    )

    # ── Shared ───────────────────────────────────────────────────
    gym_stripe_service = providers.Factory(GymStripeService, db_pool=db_pool)

    # ── Payments (Stripe) ────────────────────────────────────────
    stripe_client = providers.Singleton(
        PaymentsStripeClient,
        secret_key=settings.stripe_secret_key,
    )
    payments_price_service = providers.Factory(
        PaymentsStripePriceService,
        stripe_client=stripe_client,
    )
    payments_membership_service = providers.Factory(
        PaymentsStripeMembershipService,
        stripe_client=stripe_client,
        price_service=payments_price_service,
    )
    payments_discount_service = providers.Factory(
        PaymentsStripeDiscountService,
        stripe_client=stripe_client,
    )
    payments_members_service = providers.Factory(
        PaymentsStripeMembersService,
        stripe_client=stripe_client,
    )
    payments_subscription_service = providers.Factory(
        PaymentsStripeSubscriptionService,
        stripe_client=stripe_client,
        members_service=payments_members_service,
        price_service=payments_price_service,
        discount_service=payments_discount_service,
    )
    payments_payment_service = providers.Factory(
        PaymentsStripePaymentService,
        stripe_client=stripe_client,
        members_service=payments_members_service,
        price_service=payments_price_service,
    )

    # ── Payment Sync & Discounts ───────────────────────────────
    linked_member_discount_service = providers.Factory(
        LinkedMemberDiscountService,
        db_pool=db_pool,
    )
    membership_payment_sync_service = providers.Factory(
        MembershipPaymentSyncService,
        db_pool=db_pool,
        subscription_service=payments_subscription_service,
        gym_stripe_service=gym_stripe_service,
        linked_discount_service=linked_member_discount_service,
    )

    # ── Member Management ──────────────────────────────────────
    member_memberships_service = providers.Factory(
        MemberMembershipsService,
        db_pool=db_pool,
        payment_sync_service=membership_payment_sync_service,
        payment_service=payments_payment_service,
        gym_stripe_service=gym_stripe_service,
        subscription_service=payments_subscription_service,
    )
    members_management_service = providers.Factory(
        MembersManagementService,
        db_pool=db_pool,
        payments_members_service=payments_members_service,
    )

    discounts_service = providers.Factory(
        DiscountsService,
        db_pool=db_pool,
        gym_stripe_service=gym_stripe_service,
        stripe_discount_service=payments_discount_service,
        membership_payment_sync_service=membership_payment_sync_service,
    )

    membership_plans_service = providers.Factory(
        MembershipPlansService,
        db_pool=db_pool,
        gym_stripe_service=gym_stripe_service,
        stripe_membership_service=payments_membership_service,
        stripe_price_service=payments_price_service,
        membership_payment_sync_service=membership_payment_sync_service,
    )

    # ── Stripe Webhooks ────────────────────────────────────────
    stripe_webhook_event_log = providers.Factory(StripeWebhookEventLog)
    stripe_webhook_invoice_paid_handler = providers.Factory(InvoicePaidHandler)
    stripe_webhook_invoice_payment_failed_handler = providers.Factory(
        InvoicePaymentFailedHandler,
    )
    stripe_webhook_charge_refunded_handler = providers.Factory(
        ChargeRefundedHandler,
    )
    stripe_webhooks_service = providers.Factory(
        StripeWebhooksService,
        db_pool=db_pool,
        event_log=stripe_webhook_event_log,
        invoice_paid_handler=stripe_webhook_invoice_paid_handler,
        invoice_payment_failed_handler=stripe_webhook_invoice_payment_failed_handler,
        charge_refunded_handler=stripe_webhook_charge_refunded_handler,
    )
