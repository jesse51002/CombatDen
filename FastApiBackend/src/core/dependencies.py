from dependency_injector import containers, providers
from schema.task import TaskType

import src.shared.db_schema_path  # noqa: F401
from src.checkin.service.batch_checkin_service import BatchCheckinService
from src.checkin.service.checkin_attendees_service import (
    CheckinAttendeesService,
)
from src.checkin.service.checkin_class_resolver import (
    CheckinClassResolver,
)
from src.checkin.service.checkin_history_service import (
    CheckinHistoryService,
)
from src.checkin.service.checkin_member_gate import CheckinMemberGate
from src.checkin.service.checkin_occurrence_resolution import (
    CheckinOccurrenceResolution,
)
from src.checkin.service.checkin_remover import CheckinRemover
from src.checkin.service.checkin_reverser import CheckinReverser
from src.checkin.service.cycle_counts_service import CycleCountsService
from src.checkin.service.signup_service import SignupService
from src.checkin.service.streak_service import StreakService
from src.classes.service.classes_crud_service import ClassesCrudService
from src.classes.service.classes_exceptions_service import (
    ClassesExceptionsService,
)
from src.classes.service.classes_expander import ClassesExpander
from src.classes.service.classes_schedule_reader_service import (
    ClassesScheduleReaderService,
)
from src.classes.service.classes_undo_service import ClassesUndoService
from src.classes.service.classes_version_expander import (
    ClassesVersionExpander,
)
from src.classes.service.classes_versions_service import (
    ClassesVersionsService,
)
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
from src.ranks.service.ranks_members import RanksMembers
from src.ranks.service.ranks_presets import RanksPresets
from src.ranks.service.ranks_reads import RanksReads
from src.ranks.service.ranks_reorder import RanksReorder
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
from src.theme.service.theme_showcase_defaults_service import (
    ThemeShowcaseDefaultsService,
)
from src.theme.service.theme_showcase_service import ThemeShowcaseService
from src.uploads.service.uploads_s3_service import UploadsS3Service
from src.videos.service.member_video_profile_refresh_runner import (
    MemberVideoProfileRefreshRunner,
)
from src.videos.service.member_video_profile_service import (
    MemberVideoProfileService,
)
from src.videos.service.video_agent.video_agent_service import VideoAgentService
from src.videos.service.video_feed_refiner import VideoFeedRefiner
from src.videos.service.video_feed_service import VideoFeedService
from src.videos.service.video_query_generator import VideoQueryGenerator
from src.videos.service.video_rec_click_service import VideoRecClickService
from src.videos.service.video_recs_service import VideoRecsService
from src.videos.service.video_spec_authoring import VideoSpecAuthoring
from src.videos.service.video_spec_service import VideoSpecService
from src.videos.service.videos_service import VideosService
from src.videos.service.youtube_metadata import YouTubeMetadataClient
from src.waivers.service.waivers_service import WaiversService


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
            "src.uploads.uploads_router",
        ],
    )

    db_pool = providers.Singleton(DirectDatabasePool)
    supabase = providers.Singleton(SupabaseClient)
    auth = providers.Singleton(Auth, supabase=supabase)

    # The canonical single-shape recurrence + exception engine is pure (no
    # I/O); a single shared instance is reused everywhere.
    classes_expander = providers.Singleton(ClassesExpander)
    # The versioned expander (also pure): windows a class's schedule versions
    # by effective_from (ownership), dedups boundary days, and expands each
    # version with its own frozen timezone. Every occurrence resolution —
    # the board, check-in validation, sign-up validation, reschedule checks,
    # the mint wipe — goes through it.
    classes_version_expander = providers.Singleton(
        ClassesVersionExpander,
        expander=classes_expander,
    )

    # ── Uploads (image proxy → S3 + CloudFront CDN) ──────────────
    # Singleton, not Factory: the service holds a reusable boto3 S3 client
    # (built once in __init__ — construction loads botocore's service model
    # and signer stack, too costly to repeat per request).
    uploads_s3_service = providers.Singleton(
        UploadsS3Service,
        assets_bucket=settings.assets_bucket,
        aws_region=settings.aws_region,
        assets_cdn_base_url=settings.assets_cdn_base_url,
    )

    # ── Checkin domain (the class consumer side) ─────────────────
    # Gated lazy check-in (resolve → per-member gate), staff batch, attendance
    # streak, and per-cycle class usage (also feeds member billing detail).
    cycle_counts_service = providers.Factory(CycleCountsService, db_pool=db_pool)
    streak_service = providers.Factory(StreakService, db_pool=db_pool)
    # The member-page class-history feed (reservations + attendance +
    # no-shows) — a plain member-scoped read, no gate involvement.
    checkin_history_service = providers.Factory(
        CheckinHistoryService, db_pool=db_pool
    )
    # The ONE original-date occurrence-resolution algorithm the checkin
    # domain shares (versions + exceptions → the version expander, with the
    # reschedule window-widening) — injected by BOTH the check-in resolver
    # and the sign-up service so the two can never disagree about whether an
    # occurrence exists. The one-way checkin → classes dependency lives here.
    checkin_occurrence_resolution = providers.Factory(
        CheckinOccurrenceResolution,
        db_pool=db_pool,
        version_expander=classes_version_expander,
    )
    # Resolve a single occurrence for check-in (identity gate + the shared
    # resolution + the 2h early-check-in window). A pure read — occurrences
    # are computed, never stored.
    checkin_class_resolver = providers.Factory(
        CheckinClassResolver,
        db_pool=db_pool,
        occurrence_resolution=checkin_occurrence_resolution,
    )
    # Per-member gate + write (eligibility, capacity, plan selection, auto-end).
    checkin_member_gate = providers.Factory(
        CheckinMemberGate,
        db_pool=db_pool,
        cycle_counts_service=cycle_counts_service,
    )
    # Batch staff check-in. Resolves the occurrence ONCE via the resolver, then
    # loops the member gate over a de-duped member list — the same two seams the
    # single-check-in router injects directly.
    batch_checkin_service = providers.Factory(
        BatchCheckinService,
        resolver=checkin_class_resolver,
        member_gate=checkin_member_gate,
    )
    # Read-only: the combined signed-up-or-attended roster of one occurrence
    # (gym-local day-bounds resolve, class_signups + member_attendance join).
    checkin_attendees_service = providers.Factory(
        CheckinAttendeesService,
        db_pool=db_pool,
    )
    # Create / remove a member's sign-up (reservation) for an occurrence.
    # create() validates the occurrence via the SAME shared resolution the
    # check-in resolver injects, then its capacity check reads the same
    # signed-up-or-attended union the check-in capacity gate reads (both go
    # through CheckinQueries).
    signup_service = providers.Factory(
        SignupService,
        db_pool=db_pool,
        occurrence_resolution=checkin_occurrence_resolution,
    )
    # Shared per-member check-in reverser: delete attendance, claw back points,
    # drop a feed activity, reverse the pack auto-end — on a KNOWN occurrence, in
    # the caller's transaction, importing nothing from src.classes. Built before
    # both consumers (checkin_remover below and classes_undo_service, which loops
    # it over every attendee — the deliberate classes -> checkin dependency).
    checkin_reverser = providers.Factory(CheckinReverser)
    # Reverse one member's check-in: find the occurrence, then delegate the
    # reversal to the shared checkin_reverser for that single member.
    checkin_remover = providers.Factory(
        CheckinRemover,
        db_pool=db_pool,
        reverser=checkin_reverser,
    )

    # Un-occur (cancel) + reschedule a single occurrence. Billing-adjacent
    # (deletes member_attendance, claws back points, may clear an auto-end
    # end_date), so each op runs in one transaction. Its teardown loops the
    # shared checkin_reverser (defined above) over every attendee — a
    # deliberate classes -> checkin dependency that avoids duplicating the
    # reversal. Also HOSTS the shared reschedule engine (time-aware conflict
    # check + attendance wipe / occurred_at re-sync) AND the shared cancel
    # teardown (teardown_occurrence) that the exceptions service and the
    # versions service's wipe reuse — hence defined before all of them.
    classes_undo_service = providers.Factory(
        ClassesUndoService,
        db_pool=db_pool,
        expander=classes_expander,
        version_expander=classes_version_expander,
        reverser=checkin_reverser,
    )
    # The schedule-version MINT engine: the one writer of
    # gym_class_schedules. Minting runs the version-change wipe in the same
    # transaction (per-date: cancellations and already-ran occurrences are
    # untouched; non-surviving dates are torn down via the undo service's
    # shared teardown — attendance reversed, sign-ups deleted, the exception
    # dropped). Also owns the soft-delete wipe and the gym timezone-change
    # re-mint (which never wipes — same shape, wall-clock survival by
    # construction).
    classes_versions_service = providers.Factory(
        ClassesVersionsService,
        db_pool=db_pool,
        version_expander=classes_version_expander,
        undo_service=classes_undo_service,
    )
    # Class CRUD: identity in place; the schedule half mints versions via the
    # versions service; soft delete runs the future-keyed wipe.
    classes_crud_service = providers.Factory(
        ClassesCrudService,
        db_pool=db_pool,
        versions_service=classes_versions_service,
        default_image_url=settings.default_class_image_url,
    )
    # A reschedule (new_date) on an instance-exception upsert delegates the
    # conflict check + attendance move to the undo service's engine, then writes
    # the override row in the same transaction.
    classes_exceptions_service = providers.Factory(
        ClassesExceptionsService,
        db_pool=db_pool,
        undo_service=classes_undo_service,
    )
    classes_schedule_reader_service = providers.Factory(
        ClassesScheduleReaderService,
        db_pool=db_pool,
        version_expander=classes_version_expander,
    )

    rewards_service = providers.Factory(
        RewardsService,
        db_pool=db_pool,
        default_image_url=settings.default_reward_image_url,
    )
    rewards_redemption_service = providers.Factory(RewardsRedemptionService, db_pool=db_pool)

    # Ranks: a thin facade over four concern services. RanksPresets
    # composes RanksMembers for the shared lowest-rank backfill (seeding a
    # preset runs the same backfill as create / enable-toggle).
    ranks_members = providers.Factory(RanksMembers, db_pool=db_pool)
    ranks_reorder = providers.Factory(RanksReorder, db_pool=db_pool)
    ranks_presets = providers.Factory(
        RanksPresets,
        db_pool=db_pool,
        members=ranks_members,
    )
    ranks_reads = providers.Factory(RanksReads, db_pool=db_pool)
    ranks_service = providers.Factory(
        RanksService,
        db_pool=db_pool,
        members=ranks_members,
        reorder=ranks_reorder,
        presets=ranks_presets,
        reads=ranks_reads,
    )

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
        query_count=settings.video_query_count,
    )
    video_feed_refiner = providers.Singleton(
        VideoFeedRefiner,
        db_pool=db_pool,
        spec_service=video_spec_service,
        litellm_client=litellm_client,
        model=settings.video_llm_model,
        authoring=video_spec_authoring,
    )
    # RAG read surface: the member's video-taste profile is ONE LLM summary +
    # ONE embedding on the members row, built by the profile service (a small
    # summary model turns member facts into the taste paragraph; the embedding
    # model embeds it). The member rec surface serves one rotating-category pick
    # ranked against that embedding; the feed page optionally re-orders by it. The
    # embedding model + dim pin the same cross-service contract as the video_rag
    # DDL. Defined before video_feed_service, which now reads the embedding.
    member_video_profile_service = providers.Singleton(
        MemberVideoProfileService,
        db_pool=db_pool,
        litellm_client=litellm_client,
        embedding_model=settings.video_embedding_model,
        embedding_dim=settings.video_embedding_dim,
        summary_model=settings.video_profile_summary_model,
        refresh_cooldown_days=settings.video_profile_refresh_cooldown_days,
        attendance_window_days=settings.video_profile_attendance_window_days,
        top_classes_limit=settings.video_profile_top_classes_limit,
        recent_clicks_limit=settings.video_profile_recent_clicks_limit,
    )
    # Concern services — stateless, composed by the facade. The feed service
    # reads a member's profile embedding (read-only) for the unified feed's
    # optional personalized ordering when passed a member_id, and applies the
    # σ-scaled owner boost + decayed watch penalty from these two settings.
    video_feed_service = providers.Factory(
        VideoFeedService,
        db_pool=db_pool,
        youtube_client=youtube_metadata_client,
        profile_service=member_video_profile_service,
        bump_sigma_fraction=settings.video_feed_bump_sigma_fraction,
        watch_penalty_half_life_days=settings.video_watch_penalty_half_life_days,
    )
    # Fire-and-forget profile refresh (class-booking + video-click triggers).
    # Singleton so drain() on shutdown sees every in-flight refresh task.
    member_video_profile_refresh_runner = providers.Singleton(
        MemberVideoProfileRefreshRunner,
        profile_service=member_video_profile_service,
    )
    # The rec is a thin wrapper over the feed: it drives the category rotation
    # and records the pick, but the ranking + candidate query live in the unified
    # video_feed_service.load_feed_page (defined above; the rec calls it limit=1).
    video_recs_service = providers.Factory(
        VideoRecsService,
        db_pool=db_pool,
        profile_service=member_video_profile_service,
        feed_service=video_feed_service,
        rotation=settings.video_rec_category_rotation,
    )
    # Record a rec click: stamp clicked_at + log a video_clicked activity, then
    # fire the profile refresh via the runner above.
    video_rec_click_service = providers.Factory(
        VideoRecClickService,
        db_pool=db_pool,
        refresh_runner=member_video_profile_refresh_runner,
    )
    # Facade: composes feed + spec + RAG sub-services. Template catalog reads are
    # in PresetsTemplateService; showcase reads are in ThemeShowcaseService.
    videos_service = providers.Factory(
        VideosService,
        feed_service=video_feed_service,
        spec_service=video_spec_service,
        authoring=video_spec_authoring,
        feed_refiner=video_feed_refiner,
        recs_service=video_recs_service,
        click_service=video_rec_click_service,
    )
    # Theme: branded class/reward cards for the showcase surface.
    theme_showcase_service = providers.Factory(
        ThemeShowcaseService,
        db_pool=db_pool,
    )
    # Theme: static, category-keyed demo showcase cards from a bundled YAML
    # file (no DB) for the public standalone theme browser.
    # Singleton, not Factory: the service caches the parsed + validated YAML
    # on the instance for the process lifetime — a Factory would rebuild a
    # fresh instance (and re-read + re-validate the YAML) on every request.
    theme_showcase_defaults_service = providers.Singleton(
        ThemeShowcaseDefaultsService,
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

    # Presets: transactional import of a template_gym template into a real gym's
    # production tables. Owner-gated + email allowlist. No Stripe. Reuses the
    # canonical classes_expander to seed each imported class's past month of
    # attendance + sign-ups (so the demo gym shows realistic counts).
    presets_service = providers.Factory(
        PresetsService,
        db_pool=db_pool,
        expander=classes_expander,
        default_class_image_url=settings.default_class_image_url,
        default_reward_image_url=settings.default_reward_image_url,
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
    # classes_versions_service is the documented gyms -> classes edge: a gym
    # TIMEZONE change re-mints every live class's schedule version with the
    # new zone (wall-clock match keeps all future sign-ups / check-ins).
    # ranks_members is the documented gyms -> ranks edge: a gym SUB_RANK_TYPE
    # change reconciles every member's current_sub_index to stay leaf-valid.
    gyms_service = providers.Factory(
        GymsService,
        db_pool=db_pool,
        stripe_connect_service=gyms_stripe_connect_service,
        waivers_service=waivers_service,
        classes_versions_service=classes_versions_service,
        ranks_members=ranks_members,
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
