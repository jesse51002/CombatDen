"""InvoiceFetchSweep — twice-daily missed-webhook backstop.

Per gym Connect account it delegates to the memberships invoice fetch
(``MemberMembershipsInvoiceFetch.sweep_account``) to list the last
``settings.reconciler_invoice_lookback_days`` of Stripe activity and re-record
each object through the SAME webhook ``record`` seams. The fetch + apply engine
lives in ``memberships`` (the reconciler calls in, never the reverse); this
sweep owns only the gym iteration + the lookback window.
"""

import logging
import time

from sqlalchemy import text

from src.core.config import settings
from src.memberships.service.memberships_invoice_fetch import (
    MemberMembershipsInvoiceFetch,
)
from src.reconciler import SQL_DIR
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql
from src.shared.sweep_result import SweepResult

logger = logging.getLogger(__name__)

SWEEP_NAME = "invoice_fetch"
SECONDS_PER_DAY = 86400


class InvoiceFetchSweep:
    """Delegate a per-gym Stripe invoice / refund backfill to memberships."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        invoice_fetch: MemberMembershipsInvoiceFetch,
    ) -> None:
        self._db_pool = db_pool
        self._invoice_fetch = invoice_fetch

    async def run(self) -> SweepResult:
        """Sweep recent Stripe activity for every connected gym."""
        result = SweepResult(name=SWEEP_NAME)
        cutoff = (
            int(time.time())
            - settings.reconciler_invoice_lookback_days * SECONDS_PER_DAY
        )
        gyms = await self._list_gyms()
        for gym in gyms:
            await self._invoice_fetch.sweep_account(
                gym["gym_id"],
                gym["stripe_account_id"],
                cutoff,
                result,
            )
        logger.info(
            "Invoice fetch: gyms=%d processed=%d recorded=%d "
            "skipped=%d errors=%d",
            len(gyms),
            result.processed,
            result.changed,
            result.skipped,
            result.errors,
        )
        return result

    async def _list_gyms(self) -> list[dict]:
        """Gyms that have a Stripe Connect account."""
        sql = load_sql(SQL_DIR / "reconciler_gyms_with_connect.sql")
        async with self._db_pool.session() as session:
            res = await session.execute(text(sql))
            return [dict(row) for row in res.mappings().all()]
