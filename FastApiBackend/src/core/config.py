import enum
import logging
import sys
from typing import Final

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

    # Logging Configuration
    log_level: str = "DEBUG"

    # Scheduled reconciler (twice-daily billing safety-net sweep)
    reconciler_enabled: bool = True
    reconciler_cron_hours: list[int] = [2, 14]  # UTC hours, twice daily


# Billing cycle anchor constants
MONTHLY_BILLING_ANCHOR_DAY: Final[int] = 1  # 1st of month
WEEKLY_BILLING_ANCHOR_WEEKDAY: Final[int] = 6  # Sunday (Python weekday: Mon=0, Sun=6)

# Concurrency-lease timings — see src/shared/paying_member_lock.py
LOCK_TTL_SECONDS: Final[int] = 60  # hard cap; a crashed/stuck holder self-heals
LOCK_MAX_HOLD_SECONDS: Final[float] = 55.0  # abort the op before its lease expires (< TTL)
LOCK_ACQUIRE_TIMEOUT_SECONDS: Final[float] = 5.0  # block this long, then LockBusyError -> 409
LOCK_POLL_INTERVAL_SECONDS: Final[float] = 0.25  # retry cadence while waiting
# The lock-key namespace for a paying-parent family lease.
PAYING_MEMBER_LOCK_PREFIX: Final[str] = "paying_member_lock"

# Bulk payment-sync retry — re-attempt members that failed a pass (most often a
# transient busy family): up to BULK_SYNC_MAX_RETRIES retry passes, each after a
# BULK_SYNC_RETRY_DELAY_SECONDS wait.
BULK_SYNC_RETRY_DELAY_SECONDS: Final[int] = 10
BULK_SYNC_MAX_RETRIES: Final[int] = 3

# Scheduled reconciler — see src/reconciler/. The global sweep lock is a single
# resource_locks key so multiple app instances can't run the sweep concurrently;
# its TTL must exceed a full sweep's runtime (minutes), unlike the 60s family TTL.
RECONCILER_SWEEP_LOCK_KEY: Final[str] = "reconciler_sweep"
RECONCILER_SWEEP_LOCK_TTL_SECONDS: Final[int] = 1800
RECONCILER_INVOICE_LOOKBACK_DAYS: Final[int] = 2
RECONCILER_STRIPE_PAGE_SIZE: Final[int] = 100


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
