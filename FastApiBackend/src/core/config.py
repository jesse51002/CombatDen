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

    # Database (direct Postgres connection)
    database_url: str
    db_pool_size: int = 10
    db_max_overflow: int = 10

    # App
    app_env: AppEnv = AppEnv.DEV
    app_debug: bool = False
    cors_origins: list[str] = ["http://localhost:3000", "http://localhost:8080"]

    model_config = {"env_file": ".env", "extra": "ignore"}

    # Logging Configuration
    log_level: str = "DEBUG"


settings = Settings()


def setup_logging(log_level: str | None = None) -> None:
    """Setup logging configuration for the application.

    Args:
        log_level: The logging level (DEBUG, INFO, WARNING, ERROR, CRITICAL).
                   If not provided, uses the log_level from settings.
    """
    # Use provided log_level or fall back to settings
    level_str = log_level or settings.log_level
    level = getattr(logging, level_str.upper(), logging.INFO)

    # Create formatter
    formatter = logging.Formatter(
        fmt="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    # Setup root logger
    root_logger = logging.getLogger()
    root_logger.setLevel(logging.WARNING)  # Warning for library requests

    # Console handler
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(level)
    console_handler.setFormatter(formatter)

    # Remove existing handlers to avoid duplicates
    root_logger.handlers.clear()
    root_logger.addHandler(console_handler)

    # Set specific loggers
    logging.getLogger("uvicorn").setLevel(level)
    logging.getLogger("uvicorn.access").setLevel(logging.INFO)
    logging.getLogger("src").setLevel(level)


# Initialize logging on import
setup_logging()
