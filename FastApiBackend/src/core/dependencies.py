from dependency_injector import containers, providers
from schema.task import TaskType

import src.shared.db_schema_path  # noqa: F401
from src.classes.service.checkin.classes_checkin_service import (
    ClassesCheckinService,
)
from src.classes.service.classes_cycle_counts_service import (
    ClassesCycleCountsService,
)
from src.classes.service.classes_streak_service import ClassesStreakService
from src.core.config import settings
from src.discounts.service.discounts_service import DiscountsService
from src.gyms.service.gyms_service import GymsService
from src.gyms.service.gyms_stripe_connect_service import (
    GymsStripeConnectService,
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
from src.memberships.service.memberships_invoice_fetch import (
    MemberMembershipsInvoiceFetch,
)
from src.memberships.service.memberships_invoice_fetch_runner import (
    MembershipsInvoiceFetchRunner,
)
from src.memberships.service.memberships_refund import (
    MemberMembershipsRefund,
)
from src.memberships.service.memberships_reprice import (
    MemberMembershipsReprice,
)
from src.memberships.service.memberships_service import (
    MemberMembershipsService,
)
from src.memberships.service.memberships_upgrade import (
    MemberMembershipsUpgrade,
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
from src.plans.service.plans_service import (
    MembershipPlansService,
)
from src.ranks.service.ranks_service import RanksService
from src.reconciler.service.reconciler.reconciler_invoice_fetch_sweep import (
    InvoiceFetchSweep,
)
from src.reconciler.service.reconciler.reconciler_orphan_cleanup_sweep import (
    OrphanCleanupSweep,
)
from src.reconciler.service.reconciler.reconciler_payment_push_sweep import (
    PaymentPushSweep,
)
from src.reconciler.service.reconciler.reconciler_service import (
    ReconcilerService,
)
from src.reconciler.service.reconciler.reconciler_stale_task_sweep import (
    StaleTaskSweep,
)
from src.reconciler.service.reconciler.reconciler_subscription_orphan_sweep import (
    SubscriptionOrphanSweep,
)
from src.rewards.service.rewards_redemption_service import (
    RewardsRedemptionService,
)
from src.rewards.service.rewards_service import RewardsService
from src.shared.auth import Auth
from src.shared.database import DirectDatabasePool, SupabaseClient
from src.shared.gym_stripe_service import GymStripeService
from src.shared.payer_resolver import PayerResolver
from src.shared.paying_member_lock import PayingMemberLock
from src.shared.resource_lock import ResourceLock
from src.stripe_webhooks.service.account_updated_handler import (
    AccountUpdatedHandler,
)
from src.stripe_webhooks.service.customer_subscription_deleted_handler import (
    CustomerSubscriptionDeletedHandler,
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
from src.sync.service.sync_builder import (
    PaymentSyncBuilder,
)
from src.sync.service.sync_discounts import (
    PaymentSyncDiscounts,
)
from src.sync.service.sync_freeze import (
    PaymentSyncFreeze,
)
from src.sync.service.sync_one_time import (
    PaymentSyncOneTime,
)
from src.sync.service.sync_service import (
    PaymentSyncService,
)
from src.tasks.service.tasks_executor import TasksExecutor
from src.tasks.service.tasks_membership_reprice_handler import (
    MembershipRepriceTaskHandler,
)
from src.tasks.service.tasks_service import TasksService
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
            "src.memberships.memberships_router",
            "src.plans.plans_router",
            "src.stripe_webhooks.stripe_webhooks_router",
            # === end CRM billing router modules ===
            "src.tasks.tasks_router",
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
        api_version=settings.stripe_api_version,
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
    )
    payments_subscription_service = providers.Factory(
        PaymentsStripeSubscriptionService,
        stripe_client=stripe_client,
        members_service=payments_members_service,
        price_service=payments_price_service,
        discount_service=payments_discount_service,
    )

    # ── Payment sync ─────────────────────────────────────────────
    # Shared payer resolver, injected wherever payer (or, temporarily, parent)
    # resolution is needed: the sync, the freeze service, and the lifecycle /
    # validation callers (start, freeze, charge_card, mark_paid_cash).
    payer_resolver = providers.Factory(
        PayerResolver,
        db_pool=db_pool,
        gym_stripe_service=gym_stripe_service,
    )
    # Generic non-blocking TTL-lease lock (key-agnostic). Used by the scheduled
    # reconciler's orphan-cleanup payer check.
    resource_lock = providers.Factory(ResourceLock, db_pool=db_pool)
    # The one concurrency lock: a TTL lease keyed directly on the payer ids
    # callers pass, so no two billing ops converge the same payer's
    # subscription at once. Used by the facade, the webhook settle, and the
    # bulk fan-out.
    paying_member_lock = providers.Factory(
        PayingMemberLock,
        db_pool=db_pool,
    )
    # Standalone freeze service: the dedicated freeze/unfreeze request resolves
    # the parent then calls this directly. The main sync no longer does a
    # maintenance freeze re-apply (pause_collection is subscription-level and
    # persists across item changes), so only the explicit action uses this.
    payment_sync_freeze = providers.Factory(
        PaymentSyncFreeze,
        subscription_service=payments_subscription_service,
    )
    # Owns the discount math + resolves each line's coupons (find-or-create,
    # percent→dollar), for both real and preview. Coupon I/O is delegated to the
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
        payer_resolver=payer_resolver,
        builder=payment_sync_builder,
        paying_lock=paying_member_lock,
    )
    # Standalone one-time charge service (reuses the discount engine; does not
    # touch the recurring PaymentSyncService).
    payment_sync_one_time = providers.Factory(
        PaymentSyncOneTime,
        db_pool=db_pool,
        discounts=payment_sync_discounts,
        payment_service=payments_payment_service,
        payer_resolver=payer_resolver,
    )

    # ── Discounts ────────────────────────────────────────────────
    # Presets are plain, coupon-free gym config: no Stripe, no payment sync.
    discounts_service = providers.Factory(
        DiscountsService,
        db_pool=db_pool,
    )

    # ── Members billing/management ──────────────────────────────
    # Defined before member_memberships_service because the start op
    # injects it to promote a one-off checkout card to the saved default.
    members_management_service = providers.Factory(
        MembersManagementService,
        db_pool=db_pool,
        payments_members_service=payments_members_service,
        subscription_service=payments_subscription_service,
    )

    # ── Reprice operation (memberships — task-agnostic) ──────────
    # The append-only reprice op (cancel old row + insert successor in one
    # txn, then the convergent sync, DB-first verify-or-revert). Pure
    # membership logic: it knows nothing about how it is dispatched.
    memberships_reprice = providers.Factory(
        MemberMembershipsReprice,
        db_pool=db_pool,
        payment_sync_service=payment_sync_service,
        gym_stripe_service=gym_stripe_service,
        paying_lock=paying_member_lock,
    )

    # ── Upgrade operation (memberships — cross-plan, charge difference) ──
    # The cross-plan sibling of reprice: cancel the old row + insert a
    # successor on a DIFFERENT plan, then the convergent sync with proration
    # nets the (new - old) prorated difference. Shares the Transition-base
    # machinery; standalone (no batch), takes its own family lock.
    memberships_upgrade = providers.Factory(
        MemberMembershipsUpgrade,
        db_pool=db_pool,
        payment_sync_service=payment_sync_service,
        gym_stripe_service=gym_stripe_service,
        paying_lock=paying_member_lock,
    )

    # ── Tasks (tracked background operations) ────────────────────
    # The generic engine: TasksService (store/read + the in-task guard) and
    # TasksExecutor (run) are SEPARATE providers so the memberships↔tasks
    # graph stays acyclic. The membership_reprice handler is the ONE
    # tasks↔memberships bridge (tasks → memberships); it both creates and
    # runs membership_reprice tasks. The dependency points one way only —
    # nothing in src/memberships imports src/tasks.
    tasks_service = providers.Factory(TasksService, db_pool=db_pool)
    membership_reprice_task_handler = providers.Factory(
        MembershipRepriceTaskHandler,
        db_pool=db_pool,
        reprice_service=memberships_reprice,
        tasks_service=tasks_service,
    )
    tasks_executor = providers.Factory(
        TasksExecutor,
        db_pool=db_pool,
        handlers=providers.Dict({
            TaskType.membership_reprice: membership_reprice_task_handler,
        }),
    )

    # ── Stripe invoice/charge record handlers (the apply seams) ──
    # Defined here (not in the webhooks block below) because BOTH the on-demand
    # invoice fetch + the webhook dispatcher reuse them, and the fetch must be
    # wired before member_memberships_service (which injects its runner).
    stripe_webhook_invoice_paid_handler = providers.Factory(
        InvoicePaidHandler,
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

    # ── On-demand post-op invoice fetch ──────────────────────────
    # The deterministic fast-path that pulls a payer's new invoices from Stripe
    # right after an op (fired fire-and-forget by the runner) AND the engine the
    # reconciler's InvoiceFetchSweep delegates to. Reuses the record() seams.
    member_memberships_invoice_fetch = providers.Factory(
        MemberMembershipsInvoiceFetch,
        db_pool=db_pool,
        stripe_client=stripe_client,
        invoice_paid_handler=stripe_webhook_invoice_paid_handler,
        invoice_payment_paid_handler=(
            stripe_webhook_invoice_payment_paid_handler
        ),
        invoice_payment_failed_handler=(
            stripe_webhook_invoice_payment_failed_handler
        ),
        refund_handler=stripe_webhook_refund_handler,
        payer_resolver=payer_resolver,
    )
    # Singleton so drain() on shutdown sees every in-flight fetch task.
    memberships_invoice_fetch_runner = providers.Singleton(
        MembershipsInvoiceFetchRunner,
        invoice_fetch=member_memberships_invoice_fetch,
    )

    # ── Member memberships ───────────────────────────────────────
    member_memberships_service = providers.Factory(
        MemberMembershipsService,
        db_pool=db_pool,
        payment_sync_service=payment_sync_service,
        payment_service=payments_payment_service,
        gym_stripe_service=gym_stripe_service,
        payer_resolver=payer_resolver,
        freeze_service=payment_sync_freeze,
        paying_lock=paying_member_lock,
        payment_sync_one_time=payment_sync_one_time,
        discounts_service=discounts_service,
        reprice_service=memberships_reprice,
        upgrade_service=memberships_upgrade,
        members_management_service=members_management_service,
        waivers_service=waivers_service,
        invoice_fetch_runner=memberships_invoice_fetch_runner,
    )
    member_memberships_refund_service = providers.Factory(
        MemberMembershipsRefund,
        db_pool=db_pool,
        payment_service=payments_payment_service,
        gym_stripe_service=gym_stripe_service,
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


    # ── Membership plans ─────────────────────────────────────────
    membership_plans_service = providers.Factory(
        MembershipPlansService,
        db_pool=db_pool,
        gym_stripe_service=gym_stripe_service,
        stripe_membership_service=payments_membership_service,
        stripe_price_service=payments_price_service,
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
        waivers_service=waivers_service,
    )

    # ── Stripe webhooks ──────────────────────────────────────────
    # The 4 record handlers (invoice_paid / invoice_payment_paid /
    # invoice_payment_failed / refund) are defined ABOVE with the billing core
    # (the on-demand invoice fetch reuses them); the dispatcher references them.
    stripe_webhook_event_log = providers.Factory(StripeWebhookEventLog)
    stripe_webhook_account_updated_handler = providers.Factory(
        AccountUpdatedHandler,
    )
    stripe_webhook_customer_subscription_deleted_handler = providers.Factory(
        CustomerSubscriptionDeletedHandler,
        payment_sync_service=payment_sync_service,
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
        customer_subscription_deleted_handler=(
            stripe_webhook_customer_subscription_deleted_handler
        ),
    )
    # === end CRM billing DI providers ===

    # ── Scheduled reconciler ─────────────────────────────────────
    # Thin orchestrator behind the global sweep lock. Step-services are
    # injected here as they are added (D -> B -> A -> C).
    reconciler_orphan_cleanup_sweep = providers.Factory(
        OrphanCleanupSweep,
        db_pool=db_pool,
        resource_lock=resource_lock,
    )
    reconciler_payment_push_sweep = providers.Factory(
        PaymentPushSweep,
        db_pool=db_pool,
        payment_sync_service=payment_sync_service,
    )
    reconciler_invoice_fetch_sweep = providers.Factory(
        InvoiceFetchSweep,
        db_pool=db_pool,
        invoice_fetch=member_memberships_invoice_fetch,
    )
    # Stale-task recovery: the reconciler re-runs unfinished tracked tasks
    # whose in-process execution died (the recovery loop lives in the
    # reconciler; the tasks engine only knows how to run ONE task).
    reconciler_stale_task_sweep = providers.Factory(
        StaleTaskSweep,
        db_pool=db_pool,
        tasks_executor=tasks_executor,
    )
    reconciler_subscription_orphan_sweep = providers.Factory(
        SubscriptionOrphanSweep,
        db_pool=db_pool,
        stripe_client=stripe_client,
        subscription_service=payments_subscription_service,
    )
    reconciler_service = providers.Factory(
        ReconcilerService,
        orphan_cleanup_sweep=reconciler_orphan_cleanup_sweep,
        payment_push_sweep=reconciler_payment_push_sweep,
        invoice_fetch_sweep=reconciler_invoice_fetch_sweep,
        stale_task_sweep=reconciler_stale_task_sweep,
        subscription_orphan_sweep=reconciler_subscription_orphan_sweep,
    )
