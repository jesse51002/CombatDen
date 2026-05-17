"""Members domain service: CRUD + list / counts / detail."""

import logging
from datetime import UTC, date, datetime, timedelta
from uuid import UUID

from schema.immutable_columns import MEMBERS as MEMBERS_IMMUTABLE
from sqlalchemy import text

from src.members import SQL_DIR
from src.members.schema.members_schema import (
    MemberCreateRequest,
    MemberDetailResponse,
    MemberListItem,
    MemberListResponse,
    MemberResponse,
    MembersListRequest,
    MembersTotalCounts,
    MemberUpdateData,
    RedeemedReward,
)
from src.ranks.schema.ranks_schema import RankSummary
from src.shared.column_guard import validate_mutable_columns
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


def _status_filter_clause(view: str) -> str:
    if view == "all":
        return "TRUE"
    return f"status = '{view}'"


def _search_filter_clause(search: str | None) -> tuple[str, dict]:
    if not search:
        return "TRUE", {}
    return (
        "(first_name ILIKE :search "
        "OR last_name ILIKE :search "
        "OR COALESCE(email, '') ILIKE :search)"
    ), {"search": f"%{search}%"}


def _current_week_monday() -> date:
    today = datetime.now(UTC).date()
    return today - timedelta(days=today.weekday())


def _rank_summary_from_row(row: dict) -> RankSummary | None:
    """Build a ``RankSummary`` from the aliased ``rank_*`` columns
    produced by a member-row LEFT JOIN on gym_ranks. Returns None
    when the join produced NULLs (member has no current rank)."""
    rank_id = row.get("rank_rank_id")
    if rank_id is None:
        return None
    return RankSummary(
        rank_id=rank_id,
        main_name=row["rank_main_name"],
        sub_name=row["rank_sub_name"],
        color=row.get("rank_color"),
        image_url=row.get("rank_image_url"),
        main_rank_num_order=row["rank_main_rank_num_order"],
        sub_rank_num_order=row["rank_sub_rank_num_order"],
    )


def _count_streak(week_starts: set[date]) -> int:
    """Walk back from this week through consecutive attended weeks."""
    current_monday = _current_week_monday()
    previous_monday = current_monday - timedelta(weeks=1)

    if current_monday in week_starts:
        cursor = current_monday
    elif previous_monday in week_starts:
        cursor = previous_monday
    else:
        return 0

    streak = 0
    while cursor in week_starts:
        streak += 1
        cursor -= timedelta(weeks=1)
    return streak


class MembersService:
    """All members operations."""

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    @staticmethod
    def _row_to_list_item(row: dict) -> MemberListItem:
        """Map a list_members row (with joined rank_* columns) to a
        MemberListItem with a nested current_rank."""
        return MemberListItem(
            member_id=row["member_id"],
            first_name=row["first_name"],
            last_name=row["last_name"],
            email=row.get("email"),
            status=row["status"],
            last_class_days_ago=row.get("last_class_days_ago"),
            points_balance=row["points_balance"],
            current_rank=_rank_summary_from_row(row),
        )

    async def create_member(
        self,
        request: MemberCreateRequest,
    ) -> MemberResponse:
        """Insert a member row."""
        params = {
            "gym_id": str(request.gym_id),
            "user_id": str(request.user_id) if request.user_id else None,
            "first_name": request.first_name,
            "last_name": request.last_name,
            "email": request.email,
            "trial_start_date": request.trial_start_date,
            "trial_end_date": request.trial_end_date,
            "fully_active_start_date": request.fully_active_start_date,
            "inactive_start_date": request.inactive_start_date,
            "current_rank_id": (str(request.current_rank_id) if request.current_rank_id else None),
        }
        sql = load_sql(SQL_DIR / "insert_member.sql")
        row = await self._db_pool.execute_with_retry(sql, params)
        if not row:
            raise RuntimeError("INSERT did not return a row")
        return MemberResponse(**row)

    async def update_member(
        self,
        member_id: UUID,
        data: MemberUpdateData,
    ) -> MemberResponse:
        """Update mutable fields on a member row."""
        update_fields = data.model_dump(exclude_unset=True)
        if not update_fields:
            raise ValueError("No fields provided to update")

        validate_mutable_columns(
            MEMBERS_IMMUTABLE,
            set(update_fields.keys()),
        )

        normalized: dict[str, object] = {}
        for key, value in update_fields.items():
            if isinstance(value, UUID):
                normalized[key] = str(value)
            else:
                normalized[key] = value

        set_clause = ", ".join(f"{col} = :{col}" for col in normalized)
        sql = load_sql(
            SQL_DIR / "update_member.sql",
            {"set_clause": set_clause},
        )

        params = {**normalized, "member_id": str(member_id)}
        row = await self._db_pool.execute_with_retry(sql, params)
        if not row:
            raise ValueError("Member not found")
        return MemberResponse(**row)

    async def get_member(self, member_id: UUID) -> MemberResponse:
        """Read a single member row."""
        sql = load_sql(SQL_DIR / "get_member.sql")
        async with self._db_pool.session() as session:
            row = (
                (await session.execute(text(sql), {"member_id": str(member_id)}))
                .mappings()
                .fetchone()
            )
        if not row:
            raise ValueError("Member not found")
        return MemberResponse(**row)

    async def list_members(
        self,
        request: MembersListRequest,
    ) -> MemberListResponse:
        """Paginated members list filtered by status + search."""
        status_clause = _status_filter_clause(request.requested_view)
        search_clause, search_params = _search_filter_clause(request.search)

        list_sql = load_sql(
            SQL_DIR / "list_members.sql",
            {"status_filter": status_clause, "search_filter": search_clause},
        )
        count_sql = load_sql(
            SQL_DIR / "list_members_count.sql",
            {"status_filter": status_clause, "search_filter": search_clause},
        )

        params = {
            "gym_id": str(request.gym_id),
            "limit": request.limit,
            "offset": request.offset,
            **search_params,
        }
        count_params = {
            "gym_id": str(request.gym_id),
            **search_params,
        }

        async with self._db_pool.session() as session:
            list_rows = (await session.execute(text(list_sql), params)).mappings().all()
            total_row = (
                (await session.execute(text(count_sql), count_params)).mappings().fetchone()
            )

        items = [self._row_to_list_item(dict(row)) for row in list_rows]
        total = int(total_row["total"]) if total_row else 0
        return MemberListResponse(items=items, total=total)

    async def total_counts(self, gym_id: UUID) -> MembersTotalCounts:
        """Unfiltered counts per status for a gym."""
        sql = load_sql(SQL_DIR / "counts_members.sql")
        async with self._db_pool.session() as session:
            row = (await session.execute(text(sql), {"gym_id": str(gym_id)})).mappings().fetchone()

        if not row:
            return MembersTotalCounts(all=0, trial=0, active=0, inactive=0)

        return MembersTotalCounts(
            all=int(row["all_count"]),
            trial=int(row["trial_count"]),
            active=int(row["active_count"]),
            inactive=int(row["inactive_count"]),
        )

    async def get_member_detail(
        self,
        member_id: UUID,
    ) -> MemberDetailResponse:
        """Full detail with redeemed rewards + class streak."""
        detail_sql = load_sql(SQL_DIR / "member_detail.sql")
        redemption_sql = load_sql(SQL_DIR / "member_redemptions.sql")
        streak_sql = load_sql(SQL_DIR / "member_streak.sql")

        async with self._db_pool.session() as session:
            detail_row = (
                (
                    await session.execute(
                        text(detail_sql),
                        {"member_id": str(member_id)},
                    )
                )
                .mappings()
                .fetchone()
            )

            if not detail_row:
                raise ValueError("Member not found")

            redemption_rows = (
                (
                    await session.execute(
                        text(redemption_sql),
                        {"member_id": str(member_id)},
                    )
                )
                .mappings()
                .all()
            )

            streak_rows = (
                await session.execute(
                    text(streak_sql),
                    {"member_id": str(member_id)},
                )
            ).all()

        week_starts = {row[0] for row in streak_rows}
        streak = _count_streak(week_starts)

        redeemed = [RedeemedReward(**dict(row)) for row in redemption_rows]

        detail_dict = dict(detail_row)
        current_rank = _rank_summary_from_row(detail_dict)
        for key in (
            "rank_rank_id",
            "rank_main_name",
            "rank_sub_name",
            "rank_color",
            "rank_image_url",
            "rank_main_rank_num_order",
            "rank_sub_rank_num_order",
        ):
            detail_dict.pop(key, None)

        return MemberDetailResponse(
            **detail_dict,
            current_rank=current_rank,
            class_streak_weeks=streak,
            redeemed_rewards=redeemed,
        )
