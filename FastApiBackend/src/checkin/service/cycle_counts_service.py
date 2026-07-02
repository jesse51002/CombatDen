"""Per-membership class usage + coverage at a reference instant.

The one loader behind both the check-in gate and the member-detail usage
bridge. With no reference instant it reads exactly like before — coverage
and usage anchored on NOW (the current billing cycle). The check-in gate
passes the OCCURRENCE'S start instant instead, which makes retro check-ins
correct end-to-end:

* ``covers_reference`` — the membership was ACTIVE at the occurrence's
  gym-local date (started on/before it, not ended/cancelled by it, not
  frozen across it) — computed in ``classes_all_memberships.sql``. An ended
  trial still covers a class that ran inside its window; a membership
  started after the occurrence does not cover it.
* Usage counts in the billing cycle CONTAINING the occurrence: the SQL
  counts the CURRENT window; when the reference falls before a recurring
  membership's current window, the containing window is derived here by
  stepping the anchor (``last_paid_date | start_date``) back by the plan's
  duration (``relativedelta`` — never manual month math) and that item's
  usage is re-counted over it (``checkin_item_usage_window.sql``).
  Documented approximation: anchor-stepping assumes regular periods, so a
  cycle whose anchor shifted (repricing, freezes) recounts approximately.
  Trial / one_time packs are lifetime buckets — their window never moves.
"""

from collections import defaultdict
from datetime import date, datetime
from uuid import UUID

from dateutil.relativedelta import relativedelta
from schema.membership_plan import PlanType
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.checkin import SQL_DIR
from src.checkin.schema.cycle_counts_schema import (
    CheckinCycleCountsRequest,
    CheckinCycleCountsResponse,
    MembershipUsage,
    UserCycleCounts,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql


class CycleCountsService:
    """Counts classes used per membership within each plan's billing cycle.

    Args:
        db_pool: Injected database connection pool.
    """

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    async def get_cycle_counts(
        self,
        request: CheckinCycleCountsRequest,
        reference_instant: datetime | None = None,
    ) -> CheckinCycleCountsResponse:
        """Get per-membership coverage + class usage at a reference instant.

        Args:
            request: Gym and member IDs to query.
            reference_instant: The instant coverage / cycle windows are
                evaluated at — the occurrence's effective start for a
                check-in gate call. None (default) evaluates at now, the
                plain current-cycle read.

        Returns:
            Per-user, per-membership usage with remaining capacity.
        """
        params = {
            "gym_id": str(request.gym_id),
            "member_ids": [str(uid) for uid in request.member_ids],
            "reference_instant": reference_instant,
        }

        sql = load_sql(SQL_DIR / "classes_all_memberships.sql")

        async with self._db_pool.session() as session:
            result = await session.execute(text(sql), params)
            rows = [dict(row) for row in result.mappings().all()]
            if reference_instant is not None:
                for row in rows:
                    await self._recount_for_reference(session, row)

        return self._build_response(rows)

    async def _recount_for_reference(
        self,
        session: AsyncSession,
        row: dict,
    ) -> None:
        """Re-count one membership's usage when the reference falls in a
        PAST billing cycle — mutates ``row`` in place.

        Only a finite recurring membership has moving cycle windows worth
        recounting: unlimited plans never gate on usage, and trial /
        one_time packs consume one lifetime bucket the current-window count
        already covers. A reference inside the current window keeps the
        SQL's count untouched (the regression guard: current-occurrence
        behavior is exactly the old behavior).
        """
        if (
            PlanType(row["plan_type"]) != PlanType.recurring
            or row["class_count"] is None
        ):
            return
        anchor = row["last_paid_date"] or row["start_date"]
        reference_date = row["reference_date"]
        if anchor is None or reference_date >= anchor:
            return
        period = self._plan_period(
            row["duration_amount"], row["duration_unit"]
        )
        if period is None:
            return
        window_start, window_end = self._containing_window(
            anchor, period, reference_date
        )
        used = await self._count_window(
            session, row["item_id"], window_start, window_end
        )
        row["classes_used"] = used
        row["classes_remaining"] = max(row["class_count"] - used, 0)

    @staticmethod
    def _plan_period(
        duration_amount: int | None, duration_unit: str | None
    ) -> relativedelta | None:
        """The plan's billing period as a relativedelta (None when the plan
        carries no duration — a pure class-count pack)."""
        if duration_amount is None or duration_unit is None:
            return None
        if duration_unit == "week":
            return relativedelta(weeks=duration_amount)
        if duration_unit == "month":
            return relativedelta(months=duration_amount)
        if duration_unit == "year":
            return relativedelta(years=duration_amount)
        return None

    @staticmethod
    def _containing_window(
        anchor: date,
        period: relativedelta,
        reference_date: date,
    ) -> tuple[date, date]:
        """The billing window containing ``reference_date``, derived by
        stepping ``anchor`` (the CURRENT window's start) backward one period
        at a time. The caller guarantees ``reference_date < anchor``."""
        window_start = anchor
        while window_start > reference_date:
            window_start = window_start - period
        return window_start, window_start + period

    async def _count_window(
        self,
        session: AsyncSession,
        item_id: UUID,
        window_start: date,
        window_end: date,
    ) -> int:
        """Attendance drawn against one membership inside an explicit
        historical window."""
        row = (
            (
                await session.execute(
                    text(
                        load_sql(SQL_DIR / "checkin_item_usage_window.sql")
                    ),
                    {
                        "item_id": str(item_id),
                        "window_start": window_start,
                        "window_end": window_end,
                    },
                )
            )
            .mappings()
            .fetchone()
        )
        return int(row["classes_used"]) if row else 0

    @staticmethod
    def _build_response(rows: list[dict]) -> CheckinCycleCountsResponse:
        """Build structured response from combined query rows.

        Args:
            rows: SQL rows with membership info and classes_used.

        Returns:
            Structured response with remaining capacity computed.
        """
        user_memberships: dict[UUID, list[MembershipUsage]] = defaultdict(list)

        for row in rows:
            uid = row["member_id"]

            # classes_remaining is clamped at 0 (NULL stays NULL for unlimited)
            # by the SQL CASE/GREATEST (and the historical recount mirrors the
            # clamp), so an over-drawn pack never goes negative.
            user_memberships[uid].append(
                MembershipUsage(
                    item_id=row["item_id"],
                    plan_id=row["plan_id"],
                    start_date=row["start_date"],
                    plan_type=PlanType(row["plan_type"]),
                    status=row["status"],
                    covers_reference=row["covers_reference"],
                    class_count=row["class_count"],
                    classes_used=row["classes_used"],
                    classes_remaining=row["classes_remaining"],
                    renew_date=row["next_due_date"],
                    end_date=row["end_date"],
                )
            )

        users = [
            UserCycleCounts(member_id=uid, memberships=memberships)
            for uid, memberships in user_memberships.items()
        ]

        return CheckinCycleCountsResponse(users=users)
