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


class SyncNotConfirmedError(Exception):
    """A DB-first sync returned but its change was not confirmed on Stripe.

    Raised by ``sync_or_revert`` when the post-sync verify shows the
    ``stripe_sync_status`` writeback did not land (so Stripe is not in sync with
    the DB change). The caller's DB change has already been reverted, so the DB
    stays consistent with Stripe.
    """


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


async def sync_or_revert(
    sync_fn: Callable[[], Coroutine[Any, Any, Any]],
    revert_fn: Callable[[], Coroutine[Any, Any, Any]],
    *,
    entity_name: str,
    crm_pk: str,
    verify_fn: Callable[[], Coroutine[Any, Any, bool]] | None = None,
) -> None:
    """Run a DB-first sync, confirm it landed, and revert the DB change if not.

    The DB-first contract: the caller has already written its desired state to
    the DB, then calls the param-less payment sync, which re-derives the desired
    state from the DB, converges Stripe, and writes the result back (notably
    ``stripe_sync_status``). This helper runs that sync and then **verifies the
    writeback actually stamped the expected status**, so the DB never drifts out
    of sync with Stripe:

    - If ``sync_fn`` raises, the DB change is reverted and the original error
      propagates.
    - If ``verify_fn`` is given and returns ``False`` (the column was not
      updated -> Stripe did not take the change), the DB change is reverted and
      ``SyncNotConfirmedError`` is raised.

    ``revert_fn`` is best-effort: if the revert itself fails it is logged, not
    masked, so the primary error always reaches the caller. ``verify_fn`` is
    optional — callers whose DB change does not map to a single membership-row
    status transition (e.g. link/unlink, freeze) pass only revert-on-exception.

    Known residual (documented in the ``sync-guide`` skill): if Stripe converged
    but the writeback failed to stamp the column (rare — it is the last step),
    this reverts the DB change while Stripe holds it. The idempotent re-sync /
    reconciler reconciles that on the next run. This keeps the DB in sync with
    Stripe "as much as possible" without a full saga.

    Args:
        sync_fn: Async callable that runs the payment sync.
        revert_fn: Async callable that undoes the caller's DB change.
        entity_name: Human-readable name for logging.
        crm_pk: The CRM primary key of the affected row.
        verify_fn: Async callable returning ``True`` iff the writeback stamped
            the expected ``stripe_sync_status``.
    """
    try:
        await sync_fn()
    except Exception:
        await _safe_revert(revert_fn, entity_name, crm_pk)
        raise

    if verify_fn is not None and not await verify_fn():
        await _safe_revert(revert_fn, entity_name, crm_pk)
        raise SyncNotConfirmedError(
            f"Sync did not confirm on Stripe for {entity_name} {crm_pk}; "
            f"reverted the DB change to stay in sync with Stripe"
        )


async def _safe_revert(
    revert_fn: Callable[[], Coroutine[Any, Any, Any]],
    entity_name: str,
    crm_pk: str,
) -> None:
    """Run a revert best-effort: log on failure, never mask the primary error."""
    try:
        await revert_fn()
    except Exception:
        logger.error(
            "Failed to revert %s change crm_pk=%s after an unconfirmed sync",
            entity_name,
            crm_pk,
            exc_info=True,
        )


async def staged_preview[T](
    stage_fn: Callable[[], Coroutine[Any, Any, Any]],
    cleanup_fn: Callable[[], Coroutine[Any, Any, Any]],
    preview_fn: Callable[[], Coroutine[Any, Any, T]],
) -> T:
    """Run a read-only preview against a TEMPORARILY-staged hypothetical state.

    A preview reflects a change that is not committed to the DB. So the caller
    stages the hypothetical (stamp a membership ``preview_remove``, flip a row's
    price, insert a ``preview_add`` row, …), runs the read-only preview while the
    staged state is in the DB, then **always cleans the staged state up**
    (``finally``). The preview build reads the staged rows because it runs with
    ``preview=True``; the real path excludes ``preview_*`` so it can never bill a
    staged add.

    ⚠️ **Not race-safe on its own.** A real sync on the same paying-parent family
    during the preview window can act on a staged ``preview_remove`` / flipped row
    (e.g. drop a live Stripe line) — this MUST be wrapped in the per-parent
    concurrency lock (#25) once it lands. Until then the cleanup (``finally``)
    bounds the window but does not close the race.
    """
    await stage_fn()
    try:
        return await preview_fn()
    finally:
        await cleanup_fn()
