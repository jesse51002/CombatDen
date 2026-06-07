"""Unit tests for the DB-first sync helpers (pure, no DB/Stripe).

``sync_or_revert`` is the backbone of every lifecycle caller's contract: write
the DB, sync, verify the writeback landed, revert the DB change if it did not.
``staged_preview`` runs a read-only preview against temporarily-staged state and
**always** cleans it up. ``cleanup_pending_row`` deletes a pending row after a
Stripe failure without ever masking the original error.
"""

from unittest.mock import AsyncMock

import pytest

import src.shared.db_schema_path  # noqa: F401
from src.shared.db_first_helpers import (
    SyncNotConfirmedError,
    cleanup_pending_row,
    staged_preview,
    sync_or_revert,
)

# ── sync_or_revert ──────────────────────────────────────────────────


async def test_success_without_verify_does_not_revert() -> None:
    sync_fn = AsyncMock()
    revert_fn = AsyncMock()

    await sync_or_revert(
        sync_fn, revert_fn, entity_name="membership", crm_pk="pk1"
    )

    sync_fn.assert_awaited_once()
    revert_fn.assert_not_awaited()


async def test_success_with_verify_true_does_not_revert() -> None:
    sync_fn = AsyncMock()
    revert_fn = AsyncMock()
    verify_fn = AsyncMock(return_value=True)

    await sync_or_revert(
        sync_fn,
        revert_fn,
        entity_name="membership",
        crm_pk="pk1",
        verify_fn=verify_fn,
    )

    verify_fn.assert_awaited_once()
    revert_fn.assert_not_awaited()


async def test_sync_exception_reverts_and_reraises() -> None:
    sync_fn = AsyncMock(side_effect=ValueError("stripe blew up"))
    revert_fn = AsyncMock()

    with pytest.raises(ValueError, match="stripe blew up"):
        await sync_or_revert(
            sync_fn, revert_fn, entity_name="membership", crm_pk="pk1"
        )

    revert_fn.assert_awaited_once()


async def test_verify_false_reverts_and_raises_not_confirmed() -> None:
    sync_fn = AsyncMock()
    revert_fn = AsyncMock()
    verify_fn = AsyncMock(return_value=False)

    with pytest.raises(SyncNotConfirmedError):
        await sync_or_revert(
            sync_fn,
            revert_fn,
            entity_name="membership",
            crm_pk="pk1",
            verify_fn=verify_fn,
        )

    revert_fn.assert_awaited_once()


async def test_revert_failure_does_not_mask_primary_error() -> None:
    """If sync raises AND the revert also raises, the ORIGINAL error wins."""
    sync_fn = AsyncMock(side_effect=ValueError("primary"))
    revert_fn = AsyncMock(side_effect=RuntimeError("revert also failed"))

    with pytest.raises(ValueError, match="primary"):
        await sync_or_revert(
            sync_fn, revert_fn, entity_name="membership", crm_pk="pk1"
        )

    revert_fn.assert_awaited_once()


# ── staged_preview ──────────────────────────────────────────────────


async def test_staged_preview_stages_previews_then_cleans_up() -> None:
    calls: list[str] = []

    async def stage() -> None:
        calls.append("stage")

    async def preview() -> str:
        calls.append("preview")
        return "invoice"

    async def cleanup() -> None:
        calls.append("cleanup")

    result = await staged_preview(stage, cleanup, preview)

    assert result == "invoice"
    assert calls == ["stage", "preview", "cleanup"]


async def test_staged_preview_cleans_up_even_on_preview_error() -> None:
    cleanup_fn = AsyncMock()
    stage_fn = AsyncMock()
    preview_fn = AsyncMock(side_effect=RuntimeError("preview failed"))

    with pytest.raises(RuntimeError, match="preview failed"):
        await staged_preview(stage_fn, cleanup_fn, preview_fn)

    cleanup_fn.assert_awaited_once()


# ── cleanup_pending_row ─────────────────────────────────────────────


async def test_cleanup_pending_row_calls_delete() -> None:
    delete_fn = AsyncMock()

    await cleanup_pending_row(delete_fn, "membership", "pk1")

    delete_fn.assert_awaited_once()


async def test_cleanup_pending_row_swallows_delete_failure() -> None:
    """A cleanup failure is logged, never raised, so the original Stripe error
    propagates instead of being masked by a secondary delete failure."""
    delete_fn = AsyncMock(side_effect=RuntimeError("delete failed"))

    # Must NOT raise.
    await cleanup_pending_row(delete_fn, "membership", "pk1")

    delete_fn.assert_awaited_once()
