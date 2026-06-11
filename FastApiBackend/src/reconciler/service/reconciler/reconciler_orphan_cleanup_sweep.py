"""OrphanCleanupSweep — delete stranded ``not_added`` membership rows safely.

A membership-start writes a pending row (NULL ``stripe_item_id``,
``stripe_sync_status='not_added'``) then converges Stripe under the family lock,
deleting the row if the sync does not confirm. A crash mid-op can strand the
pending row. This sweep removes such rows — but only after a **non-blocking**
acquire of that row's paying-family lock: if the lock is held an op is in flight
(leave it), if free it is a genuine orphan (delete it). The delete itself still
guards ``stripe_item_id IS NULL`` so a row confirmed in the gap is never removed.
"""

import logging
from uuid import UUID

from sqlalchemy import text

from src.core.config import PAYING_MEMBER_LOCK_PREFIX
from src.memberships import SQL_DIR as MEMBERSHIPS_SQL_DIR
from src.reconciler import SQL_DIR
from src.reconciler.service.reconciler.reconciler_result import SweepResult
from src.shared.database import DirectDatabasePool
from src.shared.payer_resolver import PayerResolver
from src.shared.resource_lock import ResourceLock
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)

SWEEP_NAME = "orphan_cleanup"


class OrphanCleanupSweep:
    """Delete orphaned ``not_added`` memberships when their family is idle."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        parent_resolver: PayerResolver,
        resource_lock: ResourceLock,
    ) -> None:
        self._db_pool = db_pool
        self._parent = parent_resolver
        self._resource_lock = resource_lock

    async def run(self) -> SweepResult:
        """Sweep every orphaned ``not_added`` row; skip any family in flight."""
        orphans = await self._list_orphans()
        result = SweepResult(name=SWEEP_NAME, processed=len(orphans))
        for orphan in orphans:
            await self._try_cleanup_one(orphan, result)
        logger.info(
            "Orphan cleanup: processed=%d deleted=%d skipped=%d errors=%d",
            result.processed,
            result.changed,
            result.skipped,
            result.errors,
        )
        return result

    async def _list_orphans(self) -> list[dict]:
        """Return all orphaned pending rows (item_id, member_id, gym_id)."""
        sql = load_sql(SQL_DIR / "reconciler_orphan_memberships.sql")
        async with self._db_pool.session() as session:
            res = await session.execute(text(sql))
            return [dict(row) for row in res.mappings().all()]

    async def _try_cleanup_one(
        self,
        orphan: dict,
        result: SweepResult,
    ) -> None:
        """Delete one orphan under its family lock, or skip if the lock is held."""
        try:
            parent = await self._parent.resolve_parent(orphan["member_id"])
        except ValueError:
            logger.warning(
                "Orphan %s: cannot resolve paying parent; leaving for next run",
                orphan["item_id"],
                exc_info=True,
            )
            result.errors += 1
            return

        key = f"{PAYING_MEMBER_LOCK_PREFIX}:{parent.member_id}"
        async with self._resource_lock.try_lock(key) as acquired:
            if not acquired:
                result.skipped += 1
                return
            await self._delete_orphan(orphan["item_id"])
            result.changed += 1

    async def _delete_orphan(self, item_id: UUID) -> None:
        """Hard-delete one pending row (reuses the guarded delete SQL)."""
        sql = load_sql(
            MEMBERSHIPS_SQL_DIR / "member_memberships_delete_pending.sql",
        )
        await self._db_pool.execute_with_retry(
            sql,
            {"item_ids": [str(item_id)]},
        )
