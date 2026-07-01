import enum
import logging
import sys

from pydantic_settings import BaseSettings


class AppEnv(enum.StrEnum):
    """Application environment."""

    DEV = "dev"
    QA = "qa"
    PROD = "prod"


class Settings(BaseSettings):
    """Application configuration loaded from environment variables."""

    # Supabase
    supabase_url: str
    supabase_anon_key: str
    supabase_service_role_key: str

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
    # Class-history materialize: how many days back ClassesMaterializer.
    # materialize_current looks (the reconciler sweep's convenience window,
    # [today - this, today + materialize_future_hours]) to backfill
    # class_history rows for PAST, non-cancelled occurrences (even
    # zero-attendee ones). A value <= 0 makes materialize_current a no-op
    # (logged warning) — it never expands or writes.
    class_history_lookback_days: int = 14
    # Class-history materialize: how far AHEAD of "now" an occurrence may be
    # materialized by ClassesMaterializer.materialize — the single shared
    # forward cutoff every caller (check-in, the schedule board, the
    # reconciler sweep) obeys, so a not-yet-started class's editable fields
    # (time / instructor) aren't frozen into class_history too early. Matches
    # the check-in-open window (checkin_opens_hours_before_start) by default.
    materialize_future_hours: int = 2

    # Check-in early window: how many hours BEFORE a class's start time check-in
    # opens. A check-in (single or batch "update attendees") for an occurrence
    # whose start is further than this in the future is rejected. 2h (not the
    # usual ~30m) so staff can check a member into several back-to-back classes
    # at once. Past / in-session occurrences are always check-in-able.
    checkin_opens_hours_before_start: int = 2

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
