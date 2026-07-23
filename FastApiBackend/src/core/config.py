import enum
import logging
import sys

from pydantic_settings import BaseSettings

# db_schema_path registers the Database python_data package on sys.path; it MUST
# run before `from schema.*`. config.py is an early importer, so keep this first
# (isort: skip stops import-sorting from reordering `schema` ahead of it).
import src.shared.db_schema_path  # noqa: F401  # isort: skip
from schema.video import VideoGenre  # isort: skip


class AppEnv(enum.StrEnum):
    """Application environment."""

    DEV = "dev"
    QA = "qa"
    PROD = "prod"


class AuthAutoconfirmPolicy(enum.StrEnum):
    """What to do when GoTrue is auto-confirming every signup.

    Identity here is the verified email claim matched against a
    ``gym_employees`` row, and "verified" is proven by
    ``auth.users.email_confirmed_at IS NOT NULL``. With GoTrue's
    ``enable_confirmations`` OFF, GoTrue stamps that column ITSELF at
    signup — so the column proves nothing and anyone can sign up as
    ``owner@somegym.com`` and be admitted.

    The default is ``fail``: an auth stack that auto-confirms leaves the
    identity model wide open, and that is not a state to boot into and
    log about. ``config.toml`` ships ``enable_confirmations = true``, so a
    correctly-started local stack passes this too — if it trips, the stack
    predates that setting and needs ``supabase stop && supabase start``.
    ``warn`` exists as a deliberate, explicit escape hatch for a throwaway
    environment holding no real data; it is never the default anywhere.
    """

    WARN = "warn"
    FAIL = "fail"


class Settings(BaseSettings):
    """Application configuration loaded from environment variables."""

    # Supabase
    supabase_url: str
    supabase_anon_key: str
    supabase_service_role_key: str

    # Startup guard on GoTrue's signup-confirmation setting (see
    # AuthAutoconfirmPolicy and src/shared/auth_settings_guard.py). The check
    # reads GoTrue's own published config at
    # {supabase_url}/auth/v1/settings; a failure to REACH GoTrue is never
    # treated as a misconfiguration and never takes the app down.
    auth_autoconfirm_policy: AuthAutoconfirmPolicy = AuthAutoconfirmPolicy.FAIL
    auth_settings_check_timeout_seconds: float = 30.0

    # Stripe
    stripe_secret_key: str
    stripe_webhook_secret: str
    stripe_connect_webhook_secret: str
    # Pin the Stripe API version so an SDK upgrade can't silently change
    # request/response shapes under us (a version bump moved fields like
    # discount.coupon -> discount.source.coupon and broke webhook captures).
    # Bump deliberately, alongside the code that handles the new shapes.
    stripe_api_version: str = "2026-05-27.dahlia"

    # Stripe Connect Express onboarding
    stripe_connect_refresh_url: str
    stripe_connect_return_url: str
    stripe_connect_express_country: str = "US"

    # Database (direct Postgres connection)
    database_url: str
    db_pool_size: int = 10
    db_max_overflow: int = 10
    db_echo: bool = False

    # App
    app_env: AppEnv = AppEnv.DEV
    app_debug: bool = False
    cors_origins: list[str] = [
        "http://localhost:8081",  # CRM admin (flutter web :8081)
        "http://localhost:8082",  # CRM theme-browser target
        "http://localhost:3000",
        "http://localhost:8080",
        "https://app.combatden.net",
        "https://themes.combatden.net",
    ]

    model_config = {"env_file": ".env", "extra": "ignore"}

    # YouTube Data API v3 — used when an owner adds a single video to a gym's
    # feed: the backend fetches the real title / channel / thumbnail / views /
    # duration / channel avatar for that id. Same key family the VideoService
    # scraper uses (a Google API key, ``AIza…``); set ``YOUTUBE_API_KEY`` in .env.
    youtube_api_key: str
    youtube_data_api_base_url: str = "https://www.googleapis.com/youtube/v3"

    # LLM layer for the videos domain. Two separate model settings because the
    # single-shot structured calls (query gen, feed refiner) use litellm (with its
    # ``provider/name`` format), while the conversational agent uses Pydantic AI's
    # explicit ``AnthropicModel`` (bare model name only). Keys default to empty so
    # the backend boots without them; set the relevant key in .env to enable calls.
    anthropic_api_key: str = ""
    openai_api_key: str = ""
    gemini_api_key: str = ""
    # litellm model string for VideoQueryGenerator + VideoFeedRefiner.
    video_llm_model: str = "anthropic/claude-sonnet-4-6"
    # Bare Anthropic model name for the Pydantic AI VideoAgentService.
    video_agent_model: str = "claude-sonnet-4-6"
    video_agent_retries: int = 3
    # Target number of YouTube search queries VideoQueryGenerator produces per
    # spec commit (VideoSpecAuthoring injects this into the generator's second
    # call). The prompt asks for ~this many; MAX_GENERATED_QUERIES is the hard
    # ceiling above it. Roughly one third land as landscape-targeted queries.
    video_query_count: int = 25

    # ── Video RAG read surface (member recs + personalized feed) ──────
    # Embedding model + dimension for the member's video-taste profile embedding
    # AND the video summaries the VideoService worker embeds. The dimension is pinned to the
    # `vector(3072)` DDL — a CROSS-SERVICE CONTRACT: it pins BOTH the
    # `video_rag.embedding` the VideoService worker writes AND the
    # `members.video_profile_embedding` this backend writes (all three must use
    # the same model + dim, they are compared by cosine). Uses the litellm
    # `provider/name` format so the provider key is resolved from the prefix
    # (gemini/ → gemini_api_key). gemini-embedding-001 outputs native 3072 dims
    # (pre-normalized at 3072 — no manual renormalization needed). Stored full
    # precision; the video_rag HNSW index runs on a halfvec cast (the `vector` type
    # can't HNSW past 2000 dims). Changing the model is a one-way door: migration +
    # full re-embed of video_rag AND members.video_profile_embedding.
    video_embedding_model: str = "gemini/gemini-embedding-001"
    video_embedding_dim: int = 3072
    # A member's video-taste profile is ONE summary + ONE embedding on the
    # members row, (re)built ONLY by `refresh_if_due` (fired fire-and-forget by
    # the class-booking + video-click triggers) at most once per this cooldown.
    # Reads never build — a member with no profile yet ranks without similarity.
    video_profile_refresh_cooldown_days: int = 3
    # Small/cheap chat model (litellm provider/name format) that turns a
    # member's facts into the one-paragraph taste summary; reuses
    # `anthropic_api_key`.
    video_profile_summary_model: str = "anthropic/claude-haiku-4-5"
    # Which member facts the taste-summary prompt is built from: the trailing
    # window (days) of attendance folded in, how many most-attended classes and
    # how many most-recent `video_clicked` videos to surface. Injected into
    # `MemberVideoProfileService` (no `settings` import in the service).
    video_profile_attendance_window_days: int = 90
    video_profile_top_classes_limit: int = 3
    video_profile_recent_clicks_limit: int = 10
    # The member rec surface serves ONE video at a time, rotating the served
    # genre category through this best-first order: the member's total served-rec
    # count modulo the list length picks the starting category, and a category
    # with no videos falls through to the next. Every member of the enum appears
    # once (educational/technical content first, lighter genres last). The pick
    # WITHIN a category is ranked by PURE cosine similarity to the member's
    # taste embedding (gym relevance when unbuilt) — no blend weights, no LIMIT
    # setting (the rec SQL is a fixed LIMIT 1).
    video_rec_category_rotation: list[VideoGenre] = [
        VideoGenre.educational,
        VideoGenre.professional,
        VideoGenre.analysis,
        VideoGenre.interview,
        VideoGenre.vlog,
        VideoGenre.news,
        VideoGenre.entertainment,
        VideoGenre.clips,
        VideoGenre.memes,
    ]
    # ── Unified feed ranking (owner boost + decayed served penalty) ────
    # The one feed read serves ONLY enriched+accepted videos, merging the owner
    # section with the latest completed run, ranked on a single axis (cosine
    # distance to the member's taste embedding when built, else gym relevance).
    # Two nudges, each scaled by the axis's own sample standard deviation (sigma)
    # so they stay proportional to the spread: an owner-added video is pulled
    # ~this fraction of a sigma NEARER, and an already-SERVED video is pushed the
    # same fraction FARTHER per prior serve (the penalty sums over each serve's
    # recommended_at — SERVE time, no clicked_at filter — exponentially decayed by
    # recency: a just-served video contributes ≈1 unit, an old serve ≈0). This
    # same read backs the member rec, so the decayed penalty is what advances the
    # rec on a re-serve (no anti-join). ~10% of the cosine spread.
    video_feed_bump_sigma_fraction: float = 0.10
    # Half-life (days) of the served (recency) penalty: a serve this many days old
    # counts half as much toward pushing its video back as a serve just now.
    video_served_penalty_half_life_days: float = 7.0

    # Asset storage (S3 + CloudFront CDN) — the same bucket ThemeService's
    # build-time asset pipeline populates (theme images, fonts, etc.). This
    # backend is the only RUNTIME writer into it (the uploads domain, e.g.
    # reward/member images uploaded live from the CRM); ThemeService only
    # writes at build time via its own scripts.
    # AWS credentials are read from the standard boto3 credential chain
    # (env vars AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY, ~/.aws/credentials,
    # or an EC2/App Runner instance role). For local upload testing, add
    # AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY to FastApiBackend/.env.
    assets_bucket: str = "combatden-assets"
    aws_region: str = "us-east-1"
    assets_cdn_base_url: str = "https://cdn.combatden.net"

    # Logging Configuration
    log_level: str = "DEBUG"

    # Scheduled reconciler (twice-daily billing safety-net sweep). Its run now
    # also recovers stale tasks (re-runs unfinished tasks whose in-process
    # execution died) — see src/reconciler/.
    reconciler_enabled: bool = True
    reconciler_cron_hours: list[int] = [2, 14]  # UTC hours, twice daily
    # Scheduled reconciler sweep tuning — see src/reconciler/. No
    # reconciler-wide lock: safety is the per-payer PayingMemberLock every
    # payment op already holds, so concurrent sweeps are safe (they only
    # repeat idempotent work).
    reconciler_invoice_lookback_days: int = 1
    reconciler_stripe_page_size: int = 100
    # Subscription-orphan sweep: only cancel a Stripe sub with no live DB link
    # once it is older than this. Without metadata we can't lock an unlinked sub
    # to its family, so a sub a live op just created (writeback not yet stamped)
    # must age past any in-flight op before it can be judged an orphan.
    reconciler_orphan_min_age_seconds: int = 3600

    # Check-in early window: how many hours BEFORE a class's start time check-in
    # opens. A check-in (single or batch "update attendees") for an occurrence
    # whose start is further than this in the future is rejected. 2h (not the
    # usual ~30m) so staff can check a member into several back-to-back classes
    # at once. Past / in-session occurrences are always check-in-able.
    checkin_opens_hours_before_start: int = 2

    # Max span a single schedule-board request may cover (start_date ..
    # end_date), in CALENDAR months. The board expands every class's
    # occurrences over the window in memory, so an unbounded range is a
    # cheap CPU/memory DoS from one authenticated call. Two months comfortably
    # covers the CRM's week view and a member browsing ahead; anything wider
    # is rejected 400. Applied in ClassesScheduleReaderService, so it guards
    # both the staff /classes/instances route and the member schedule route.
    schedule_board_max_span_months: int = 2

    # Every class HAS an image (gym_classes.image_url is NOT NULL — the
    # card/board/check-in UI leans on it): class create/update and the preset
    # import fill this platform default (a generic people-in-a-gym photo,
    # Pexels 1552242) whenever no image is provided.
    default_class_image_url: str = (
        "https://images.pexels.com/photos/1552242/pexels-photo-1552242.jpeg"
        "?auto=compress&cs=tinysrgb&w=1200"
    )

    # Every reward HAS an image (gym_rewards.image_url is NOT NULL — the
    # points-store card leans on it): reward create and the preset import
    # fill this platform default (a generic wrapped-gift-box handoff photo,
    # Pexels 5493207) whenever no image is provided.
    default_reward_image_url: str = (
        "https://images.pexels.com/photos/5493207/pexels-photo-5493207.jpeg"
        "?auto=compress&cs=tinysrgb&w=1200"
    )

    # On-demand post-op invoice fetch: right after an invoice-creating
    # membership op, pull that payer's new invoices straight from Stripe and
    # apply them (deterministic) instead of waiting on the invoice.paid /
    # invoice_payment.paid webhooks. Webhooks + the twice-daily reconciler sweep
    # remain the backstops; this is an additive fast-path that reuses the same
    # idempotent record() seams.
    invoice_fetch_on_demand_enabled: bool = True
    # Widen the created>= cutoff below the op's start time to absorb clock skew
    # between our server clock and Stripe's invoice `created` timestamp.
    invoice_fetch_buffer_seconds: int = 120
    # Bounded retry: a just-created invoice may not be paid/listable the instant
    # the op returns. Delays BETWEEN attempts (first attempt is immediate); the
    # loop stops early once the bill this op cut is applied. ~51s total.
    invoice_fetch_retry_delays_seconds: list[int] = [0, 3, 8, 15, 25]

    # Stripe invoice line-items pagination + open-invoice lookups. The embedded
    # invoice.lines page holds only Stripe's default 10, so a >10-line invoice
    # (large family / class-pack) is paged in full at this limit.
    invoice_line_items_page_limit: int = 100
    subscription_open_invoice_limit: int = 1

    # Billing cycle anchors
    monthly_billing_anchor_day: int = 1  # 1st of month
    weekly_billing_anchor_weekday: int = 6  # Sunday (Python weekday: Mon=0, Sun=6)

    # Concurrency-lease timings — see src/shared/paying_member_lock.py
    lock_ttl_seconds: int = 60  # hard cap; a crashed/stuck holder self-heals
    lock_max_hold_seconds: float = 55.0  # abort the op before its lease expires (< TTL)
    lock_acquire_timeout_seconds: float = 5.0  # block this long, then LockBusyError -> 409
    lock_poll_interval_seconds: float = 0.25  # retry cadence while waiting
    # The lock-key namespace for a payer lease.
    paying_member_lock_prefix: str = "paying_member_lock"

    # Bulk payment-sync retry — re-attempt payers that failed a pass (most
    # often a transient busy payer): up to bulk_sync_max_retries retry passes,
    # each after a bulk_sync_retry_delay_seconds wait.
    bulk_sync_retry_delay_seconds: int = 10
    bulk_sync_max_retries: int = 3

    # Tracked background tasks (src/tasks/) — per-item retry mirrors the
    # bulk-sync retry: up to task_item_max_attempts attempts,
    # task_item_retry_delay_seconds between them. A 'running' claim older than
    # task_stale_running_seconds belongs to a dead process and may be reclaimed
    # when the reconciler's stale-task recovery re-runs it (see src/reconciler/).
    task_item_max_attempts: int = 3
    task_item_retry_delay_seconds: int = 10
    task_stale_running_seconds: int = 120

    # Presets: email allowlist for the preset import endpoint.
    # Comma-separated; controls who may call POST /api/v1/gyms/{id}/presets/import.
    # The import itself is a real production write path — this gate is a demo
    # control only, not a security boundary (the owner check still applies).
    preset_import_allowed_emails: str = "owner1@test.com"


settings = Settings()


def setup_logging(log_level: str | None = None) -> None:
    """Setup logging configuration for the application.

    Args:
        log_level: The logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL).
                   If not provided, uses the log_level from settings.
    """
    level_str = log_level or settings.log_level
    level = getattr(logging, level_str.upper(), logging.INFO)

    formatter = logging.Formatter(
        fmt="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    root_logger = logging.getLogger()
    root_logger.setLevel(logging.WARNING)

    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(level)
    console_handler.setFormatter(formatter)

    root_logger.handlers.clear()
    root_logger.addHandler(console_handler)

    logging.getLogger("uvicorn").setLevel(level)
    logging.getLogger("uvicorn.access").setLevel(logging.INFO)
    logging.getLogger("src").setLevel(level)


setup_logging()
