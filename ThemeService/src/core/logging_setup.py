"""Logging configuration — one console handler at the configured level."""

from __future__ import annotations

import logging
import sys

from src.core.config import settings

LOG_FORMAT = "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
LOG_DATEFMT = "%Y-%m-%d %H:%M:%S"


def configure_logging(log_level: str | None = None) -> None:
    """Configure root logging once.

    Args:
        log_level: overrides ``settings.log_level`` when given.
    """
    level_str = log_level or settings.log_level
    level = getattr(logging, level_str.upper(), logging.INFO)

    formatter = logging.Formatter(fmt=LOG_FORMAT, datefmt=LOG_DATEFMT)

    root_logger = logging.getLogger()
    root_logger.setLevel(logging.WARNING)

    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(level)
    console_handler.setFormatter(formatter)

    root_logger.handlers.clear()
    root_logger.addHandler(console_handler)

    # The pipeline package's own logs follow the configured level.
    logging.getLogger("src").setLevel(level)
