"""Helpers for the DB-first Stripe create pattern.

DB-first creates follow: INSERT (NULL stripe ID) -> Stripe -> UPDATE
(set stripe ID). This module provides the cleanup DELETE helper when
Stripe fails. The retry logic for the final UPDATE lives on
DirectDatabasePool.execute_with_retry.
"""

from __future__ import annotations

import logging
from collections.abc import Callable, Coroutine
from typing import Any

logger = logging.getLogger(__name__)


async def cleanup_pending_row(
    delete_fn: Callable[[], Coroutine[Any, Any, Any]],
    entity_name: str,
    crm_pk: str,
) -> None:
    """Delete a pending CRM row after a Stripe failure.

    Logs but does not raise if the cleanup itself fails, so the
    original Stripe error propagates to the caller.

    Args:
        delete_fn: Async callable that performs the DELETE.
        entity_name: Human-readable name for logging.
        crm_pk: The CRM primary key of the row being deleted.
    """
    try:
        await delete_fn()
    except Exception:
        logger.error(
            "Failed to clean up pending %s row crm_pk=%s",
            entity_name,
            crm_pk,
            exc_info=True,
        )
