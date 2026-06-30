from dependency_injector import containers, providers
from schema.task import TaskType

import src.shared.db_schema_path  # noqa: F401
from src.checkin.service.batch_checkin_service import BatchCheckinService
from src.checkin.service.checkin_member_gate import CheckinMemberGate
from src.checkin.service.checkin_occurrence_resolver import (
    CheckinOccurrenceResolver,
)
from src.checkin.service.checkin_service import CheckinService
from src.checkin.service.cycle_counts_service import CycleCountsService
from src.checkin.service.streak_service import StreakService
from src.classes.service.classes_crud_service import ClassesCrudService
from src.classes.service.classes_exceptions_service import (
    ClassesExceptionsService,
)
from src.classes.service.classes_expander import ClassesExpander
from src.classes.service.classes_materializer import ClassesMaterializer
from src.classes.service.classes_schedule_reader_service import (
    ClassesScheduleReaderService,
)
from src.classes.service.classes_undo_service import ClassesUndoService
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
from src.presets.service.presets_service import PresetsService
from src.presets.service.presets_template_service import PresetsTemplateService
from src.ranks.service.ranks_service import RanksService
from src.reconciler.service.reconciler.reconciler_class_history_sweep import (
    ClassHistorySweep,
)
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
from src.shared.litellm_client import LiteLLMClient
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
from src.theme.service.theme_showcase_service import ThemeShowcaseService
from src.videos.service.video_agent.video_agent_service import VideoAgentService
from src.videos.service.video_feed_refiner import VideoFeedRefiner
from src.videos.service.video_feed_service import VideoFeedService
from src.videos.service.video_query_generator import VideoQueryGenerator
from src.videos.service.video_spec_authoring import VideoSpecAuthoring
from src.videos.service.video_spec_service import VideoSpecService
from src.videos.service.videos_service import VideosService
from src.videos.service.youtube_metadata import YouTubeMetadataClient
from src.waivers.service.waivers.waivers_service import WaiversService


class DependencyInjector(containers.DeclarativeContainer):
    """Application dependency injection container.

    Add new domain modules to wiring_config.modules
    when they use @inject with Provide[...].
    """

    wiring_config = containers.WiringConfiguration(
        modules=[
            "src.main",
            "src.checkin.checkin_router",
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
            "src.videos.videos_router",
            "src.presets.presets_router",
            "src.theme.theme_router",
        ],
    )

    db_pool = providers.Singleton(DirectDatabasePool)
    supabase = providers.Singleton(SupabaseClient)
    auth = providers.Singleton(Auth, supabase=supabase)

    # The canonical recurrence + exception expander is pure (no I/O), so a
    # single shared instance is reused by the check-in resolve seam, the
    # exception reschedule-conflict check, the schedule reader, the presets
    # importer, and the reconciler's class-history sweep.
    classes_expander = providers.Singleton(ClassesExpander)
    # Lazy find-or-create of the class_history occurrence (idempotent +
    # race-safe via uq_class_history_occurrence).
    classes_materializer = providers.Factory(
        ClassesMaterializer,
        db_pool=db_pool,
    )

    # ── Checkin domain (the class consumer side) ─────────────────
    # Gated lazy check-in (resolve → per-member gate), staff batch, attendance
    # streak, and per-cycle class usage (also feeds member billing detail).
    cycle_counts_service = providers.Factory(CycleCountsService, db_pool=db_pool)
    streak_service = providers.Factory(StreakService, db_pool=db_pool)
    # Resolve + lazily materialize a single occurrence. Injects the pure
    # expander + the materializer (both stay in classes) — the one-way
    # checkin → classes dependency.
    checkin_occurrence_resolver = providers.Factory(
        CheckinOccurrenceResolver,
        db_pool=db_pool,
        expander=classes_expander,
        materializer=classes_materializer,
    )
    # Per-member gate + write (eligibility, capacity, plan selection, auto-end).
    checkin_member_gate = providers.Factory(
        CheckinMemberGate,
        db_pool=db_pool,
        cycle_counts_service=cycle_counts_service,
    )
    # Facade: composes resolve + per-member gate.
    checkin_service = providers.Factory(
        CheckinService,
        resolver=checkin_occurrence_resolver,
        member_gate=checkin_member_gate,
    )
    # Batch staff check-in. Resolves the occurrence ONCE via the facade's
    # seams, then loops checkin_member over a de-duped member list. Reuses
    # checkin_service — does not re-wire the gate.
    batch_checkin_service = providers.Factory(
        BatchCheckinService,
        checkin_service=checkin_service,
    )

    # Class CRUD + exceptions + the schedule board.
    classes_crud_service = providers.Factory(
        ClassesCrudService,
        db_pool=db_pool,
    )
    classes_exceptions_service = providers.Factory(
        ClassesExceptionsService,
        db_pool=db_pool,
        expander=classes_expander,
    )
    classes_schedule_reader_service = providers.Factory(
        ClassesScheduleReaderService,
        db_pool=db_pool,
        expander=classes_expander,
    )
    # Phase 6: un-occur (cancel) + reschedule a single occurrence. Billing-
    # adjacent (deletes member_attendance, may clear an auto-end end_date), so
    # the cancel runs in one transaction. Reuses the pure expander to validate
    # the source occurrence and the reschedule target.
    classes_undo_service = providers.Factory(
        ClassesUndoService,
        db_pool=db_pool,
        expander=classes_expander,
    )

    rewards_service = providers.Factory(RewardsService, db_pool=db_pool)
    rewards_redemption_service = providers.Factory(RewardsRedemptionService, db_pool=db_pool)

    ranks_service = providers.Factory(RanksService, db_pool=db_pool)

    # Waivers: plain gym config (versioned documents + read-only e-sign
    # tracking), no Stripe.
    waivers_service = providers.Factory(WaiversService, db_pool=db_pool)

    # Videos: the slug-keyed template catalog + a real gym's live
    # feed/spec/showcase from the gym_video_* tables, plus the owner's feed
    # add/remove. The add fetches real metadata from the YouTube Data API. No
    # Stripe.
    youtube_metadata_client = providers.Singleton(
        YouTubeMetadataClient,
        api_key=settings.youtube_api_key,
        base_url=settings.youtube_data_api_base_url,
    )

    # Video spec domain: the LLM authoring surface for a gym's append-only spec
    # (keep/avoid criteria + search queries). litellm drives the single-shot
    # structured calls; Pydantic AI drives the conversational agent. Keys default
    # to empty so the backend boots without them. No Stripe.
    # Sub-services are defined BEFORE videos_service (the facade that composes them).
    litellm_client = providers.Singleton(
        LiteLLMClient,
        anthropic_api_key=settings.anthropic_api_key,
        openai_api_key=settings.openai_api_key,
        gemini_api_key=settings.gemini_api_key,
    )
    video_spec_service = providers.Singleton(
        VideoSpecService,
        db_pool=db_pool,
    )
    video_query_generator = providers.Singleton(
        VideoQueryGenerator,
        litellm_client=litellm_client,
        model=settings.video_llm_model,
    )
    video_spec_authoring = providers.Singleton(
        VideoSpecAuthoring,
        spec_service=video_spec_service,
        query_generator=video_query_generator,
    )
    video_feed_refiner = providers.Singleton(
        VideoFeedRefiner,
        db_pool=db_pool,
        spec_service=video_spec_service,
        litellm_client=litellm_client,
        model=settings.video_llm_model,
        authoring=video_spec_authoring,
    )
    # Concern services — stateless, composed by the facade.
    video_feed_service = providers.Factory(
        VideoFeedService,
        db_pool=db_pool,
        youtube_client=youtube_metadata_client,
    )
    # Facade: composes feed + spec sub-services. Template catalog reads are in
    # PresetsTemplateService; showcase reads are in ThemeShowcaseService.
    videos_service = providers.Factory(
        VideosService,
        feed_service=video_feed_service,
        spec_service=video_spec_service,
        authoring=video_spec_authoring,
        feed_refiner=video_feed_refiner,
    )
    # Theme: branded class/reward cards for the showcase surface.
    theme_showcase_service = providers.Factory(
        ThemeShowcaseService,
        db_pool=db_pool,
    )
    # Presets: template catalog reads (list, detail, feed ids).
    presets_template_service = providers.Factory(
        PresetsTemplateService,
        db_pool=db_pool,
    )
    # The conversational agent builds its Pydantic AI Agent internally with an
    # explicit AnthropicModel — no env writes. Singleton: VideoAgentService has
    # no per-request mutable state (message history + gym_id are call arguments,
    # not instance state). The injected videos_service (and its deps) are also
    # stateless per-request — DB calls go through async context managers on the
    # shared pool, so pinning one instance is safe.
    video_agent_service = providers.Singleton(
        VideoAgentService,
        videos_service=videos_service,
        model_name=settings.video_agent_model,
        retries=settings.video_agent_retries,
        anthropic_api_key=settings.anthropic_api_key,
    )

    # Presets: transactional import of a video_gym template into a real gym's
    # production tables. Owner-gated + email allowlist. No Stripe. Reuses the
    # canonical classes_expander to seed each imported class's past month of
    # class_history + attendance (so the demo gym shows realistic counts).
    presets_service = providers.Factory(
        PresetsService, db_pool=db_pool, expander=classes_expander
    )

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
    # Shared payer resolver, injected wherever payer resolution is needed: the
    # sync and the lifecycle / validation callers (start, charge_card,
    # mark_paid_cash).
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
        payment_service=payments_payment_service,
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
    # NON-billing class-history materialize sweep: backfills class_history rows
    # for past, non-cancelled class occurrences via the existing idempotent
    # expander + materializer. Independent of every billing step.
    reconciler_class_history_sweep = providers.Factory(
        ClassHistorySweep,
        db_pool=db_pool,
        expander=classes_expander,
        materializer=classes_materializer,
    )
    reconciler_service = providers.Factory(
        ReconcilerService,
        orphan_cleanup_sweep=reconciler_orphan_cleanup_sweep,
        payment_push_sweep=reconciler_payment_push_sweep,
        invoice_fetch_sweep=reconciler_invoice_fetch_sweep,
        stale_task_sweep=reconciler_stale_task_sweep,
        subscription_orphan_sweep=reconciler_subscription_orphan_sweep,
        class_history_sweep=reconciler_class_history_sweep,
    )
