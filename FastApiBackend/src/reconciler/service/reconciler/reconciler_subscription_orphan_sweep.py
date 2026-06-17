"""SubscriptionOrphanSweep — cancel Stripe subscriptions with no live DB link.

The reverse of ``OrphanCleanupSweep`` (which deletes DB rows with no Stripe line):
this finds live Stripe subscriptions whose items map to NO live membership row and
cancels them. A subscription is stranded on Stripe when its DB membership was
reverted / deleted (a start / cancel revert, or an orphan-cleanup of a
``not_added`` row) while Stripe still held the subscription — left alone it keeps
billing a member who no longer has that membership.

Linkage is by subscription-ITEM id against the live membership rows
(``stripe_sync_status`` ``applied``); a ``deleted`` row is NOT a
live link (and the filtered view does not hide ``deleted``, so the read goes to
the unfiltered base with an explicit status filter). Runs LAST in the reconciler
(after the push sweep re-links any real sub), and skips subscriptions younger than
``settings.reconciler_orphan_min_age_seconds`` so a sub a live op just created
(writeback not yet stamped) is never mistaken for an orphan. Cancels immediately
via the payments cancel primitive (idempotent — a no-op for an already-cancelled
sub). Lists per Connect account directly off the Stripe client, mirroring
``InvoiceFetchSweep``.
"""

import logging
import time
from collections.abc import AsyncGenerator, Awaitable, Callable
from typing import Any
from uuid import uuid4

from sqlalchemy import text

from src.core.config import settings
from src.payments.schema.payments_members_schema import (
    PaymentsSubscriptionCancelRequest,
)
from src.payments.service.payments_stripe_client import PaymentsStripeClient
from src.payments.service.subscription import (
    PaymentsStripeSubscriptionService,
)
from src.reconciler import SQL_DIR
from src.reconciler.service.reconciler.reconciler_result import SweepResult
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)

SWEEP_NAME = "subscription_orphans"


class SubscriptionOrphanSweep:
    """Cancel live Stripe subscriptions that map to no live membership row."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        stripe_client: PaymentsStripeClient,
        subscription_service: PaymentsStripeSubscriptionService,
    ) -> None:
        self._db_pool = db_pool
        self._stripe = stripe_client.client
        self._subscription_service = subscription_service

    async def run(self) -> SweepResult:
        """Cancel orphan subscriptions on every connected Stripe account."""
        result = SweepResult(name=SWEEP_NAME)
        min_created = (
            int(time.time()) - settings.reconciler_orphan_min_age_seconds
        )
        accounts = await self._list_accounts()
        for account_id in accounts:
            await self._sweep_account(account_id, min_created, result)
        logger.info(
            "Subscription orphans: accounts=%d processed=%d cancelled=%d "
            "skipped=%d errors=%d",
            len(accounts),
            result.processed,
            result.changed,
            result.skipped,
            result.errors,
        )
        return result

    async def _list_accounts(self) -> list[str]:
        """Distinct Stripe Connect account ids to sweep (deduped)."""
        sql = load_sql(SQL_DIR / "reconciler_gyms_with_connect.sql")
        async with self._db_pool.session() as session:
            res = await session.execute(text(sql))
            return sorted(
                {row["stripe_account_id"] for row in res.mappings().all()}
            )

    async def _sweep_account(
        self,
        account_id: str,
        min_created: int,
        result: SweepResult,
    ) -> None:
        """List + judge every non-cancelled subscription on one account."""
        opts = PaymentsStripeClient.connect_opts_readonly(account_id)
        params = {"limit": settings.reconciler_stripe_page_size}
        async for sub in self._iter(
            self._stripe.v1.subscriptions.list_async, params, opts
        ):
            await self._consider_sub(sub, account_id, min_created, result)

    async def _consider_sub(
        self,
        sub: Any,
        account_id: str,
        min_created: int,
        result: SweepResult,
    ) -> None:
        """Cancel one subscription iff it is an aged, unlinked orphan."""
        result.processed += 1
        # Age guard: never act on a sub a live op may have just created.
        if int(sub.get("created") or 0) > min_created:
            result.skipped += 1
            return
        items = sub.get("items") or {}
        # If we can't enumerate ALL of a sub's items, we can't safely judge it
        # orphan (a hidden item might be the live link) — leave it.
        if items.get("has_more"):
            logger.warning(
                "Subscription %s has more items than one page; "
                "skipping orphan check",
                sub.get("id"),
            )
            result.skipped += 1
            return
        item_ids = [it["id"] for it in items.get("data", [])]
        if await self._has_live_link(item_ids):
            return
        await self._cancel_orphan(sub.get("id"), account_id, result)

    async def _has_live_link(self, item_ids: list[str]) -> bool:
        """True iff any item id maps to a live ('applied') row."""
        if not item_ids:
            return False
        sql = load_sql(SQL_DIR / "reconciler_linked_item_ids.sql")
        async with self._db_pool.session() as session:
            res = await session.execute(
                text(sql),
                {"stripe_item_ids": item_ids},
            )
            return res.first() is not None

    async def _cancel_orphan(
        self,
        sub_id: str,
        account_id: str,
        result: SweepResult,
    ) -> None:
        """Cancel one orphan subscription, isolating any failure."""
        try:
            await self._subscription_service.cancel_subscription(
                PaymentsSubscriptionCancelRequest(
                    stripe_subscription_id=sub_id,
                    cancel_at_period_end=False,
                    idempotency_key=str(uuid4()),
                ),
                account_id,
            )
            result.changed += 1
            logger.warning(
                "Cancelled orphan subscription %s (no live DB link)",
                sub_id,
            )
        except Exception:
            logger.error(
                "Failed to cancel orphan subscription %s; continuing",
                sub_id,
                exc_info=True,
            )
            result.errors += 1

    async def _iter(
        self,
        list_fn: Callable[..., Awaitable[Any]],
        base_params: dict[str, Any],
        opts: Any,
    ) -> AsyncGenerator[Any]:
        """Yield every object across a paginated Stripe list."""
        starting_after: str | None = None
        while True:
            params = dict(base_params)
            if starting_after:
                params["starting_after"] = starting_after
            page = await list_fn(params=params, options=opts)
            data = list(page.data)
            for obj in data:
                yield obj
            if not data or not getattr(page, "has_more", False):
                break
            starting_after = data[-1].id
