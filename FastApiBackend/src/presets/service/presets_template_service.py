"""PresetsTemplateService — the slug-keyed template_gym* template catalog reads.

Serves the public template catalog: list all templates (paginated, filterable),
fetch one template's full detail, and load a template's feed ids (approved or
rejected). Uses the ``DirectDatabasePool`` + externalised ``.sql`` files.
"""

from __future__ import annotations

import json

from schema.video import TemplateGymFeedStatus, VideoGenre
from sqlalchemy import text

from src.presets import SQL_DIR
from src.presets.schema.presets_templates_schema import (
    VideoTemplateCard,
    VideoTemplateCatalogPage,
    VideoTemplateClassCard,
    VideoTemplateDetail,
    VideoTemplateRewardCard,
    VideoTemplateSpecView,
)
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql
from src.videos.schema.videos_big_group import EDUCATIONAL_GENRES, BigGroup
from src.videos.schema.videos_gym_type import GymType
from src.videos.schema.videos_parent_gym_type import parent_of
from src.videos.schema.videos_schema import GymVideoCard, build_feed_page_result


class PresetsTemplateService:
    """Read-only access to the slug-keyed ``template_gym*`` template catalog."""

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db = db_pool

    # ── helpers ──────────────────────────────────────────────────

    @staticmethod
    def _as_list(value: object) -> list:
        """A JSONB column as a Python list — tolerant of the driver returning
        either a decoded list or the raw JSON string."""
        if value is None:
            return []
        if isinstance(value, str):
            return json.loads(value)
        return value

    def _row_to_template(self, row: object) -> VideoTemplateDetail:
        """Build a ``VideoTemplateDetail`` from a ``presets_load_template.sql``
        row."""
        classes = (
            [
                VideoTemplateClassCard.model_validate(c)
                for c in self._as_list(row["classes"])  # type: ignore[index]
            ]
            if row["has_classes"]  # type: ignore[index]
            else None
        )
        rewards = (
            [
                VideoTemplateRewardCard.model_validate(r)
                for r in self._as_list(row["rewards"])  # type: ignore[index]
            ]
            if row["has_rewards"]  # type: ignore[index]
            else None
        )
        return VideoTemplateDetail(
            video_gym_id=row["gym_id"],  # type: ignore[index]
            theme=row["theme"],  # type: ignore[index]
            specification=VideoTemplateSpecView(
                short_videos_desc=row["short_videos_desc"],  # type: ignore[index]
                short_avoid_desc=row["short_avoid_desc"],  # type: ignore[index]
                videos_desc=row["videos_desc"],  # type: ignore[index]
                avoid_desc=row["avoid_desc"],  # type: ignore[index]
            ),
            classes=classes,
            rewards=rewards,
        )

    # ── template catalog reads ────────────────────────────────────

    async def list_template_cards(
        self, *, limit: int, offset: int, query: str | None = None
    ) -> VideoTemplateCatalogPage:
        """One page of slim template cards, sorted by id. ``query`` is an optional
        case-insensitive substring filter on slug / theme / discipline."""
        sql = load_sql(SQL_DIR / "presets_list_template_cards.sql")
        async with self._db.session() as session:
            rows = (await session.execute(text(sql))).mappings().all()
        items = [(r, self._as_list(r["gym_type"])) for r in rows]
        if query:
            needle = query.strip().lower()
            items = [
                (r, disc)
                for (r, disc) in items
                if needle in r["gym_id"].lower()
                or needle in r["theme"].lower()
                or any(needle in d.lower() for d in disc)
            ]
        total = len(items)
        cards: list[VideoTemplateCard] = []
        for (r, disc) in items[offset : offset + limit]:
            try:
                parent = parent_of(GymType(disc[0]))
            except (ValueError, KeyError, IndexError):
                # One bad/unknown discipline must not 500 the whole catalog page.
                continue
            cards.append(
                VideoTemplateCard(
                    video_gym_id=r["gym_id"],
                    gym_type=disc,
                    parent_gym_type=parent,
                    theme=r["theme"],
                    video_count=r["video_count"],
                    has_classes=r["has_classes"],
                    has_rewards=r["has_rewards"],
                )
            )
        return VideoTemplateCatalogPage(
            total=total, limit=limit, offset=offset, gyms=cards
        )

    async def load_template(
        self, video_gym_id: str
    ) -> VideoTemplateDetail | None:
        """One template's full detail by slug. Returns None when missing
        (the router maps that to 404)."""
        sql = load_sql(SQL_DIR / "presets_load_template.sql")
        async with self._db.session() as session:
            row = (
                (
                    await session.execute(
                        text(sql), {"gym_id": video_gym_id}
                    )
                )
                .mappings()
                .fetchone()
            )
        if row is None:
            return None
        return self._row_to_template(row)

    async def load_template_feed_ids(
        self, video_gym_id: str, *, rejected: bool = False
    ) -> list[str]:
        """A template's feed ids in pool-relevance order. ``rejected=True``
        serves the scan's rejected list."""
        status = (
            TemplateGymFeedStatus.rejected if rejected else TemplateGymFeedStatus.good
        )
        sql = load_sql(SQL_DIR / "presets_load_template_feed_ids.sql")
        async with self._db.session() as session:
            rows = (
                (
                    await session.execute(
                        text(sql),
                        {"video_gym_id": video_gym_id, "status": status.value},
                    )
                )
                .mappings()
                .all()
            )
        return [r["video_id"] for r in rows]

    async def load_template_feed_page(
        self,
        video_gym_id: str,
        *,
        rejected: bool = False,
        video_type: VideoGenre | None = None,
        big_group: BigGroup | None = None,
        limit: int,
        offset: int,
    ) -> tuple[list[GymVideoCard], int]:
        """Paginated template feed page with in-DB filtering.

        Joins ``template_gym_feed`` → ``video``, applies status + optional tag
        filters at the DB level, and returns ``(page, total)`` in one
        round-trip.

        ``total`` is the count of all matching rows before pagination (via
        ``COUNT(*) OVER()``). It will be 0 when the requested ``offset``
        exceeds the match count — callers should not request pages past the
        ``total`` returned by the first response.
        """
        status = (
            TemplateGymFeedStatus.rejected if rejected else TemplateGymFeedStatus.good
        )
        educational_genres = [g.value for g in EDUCATIONAL_GENRES]
        sql = load_sql(SQL_DIR / "presets_load_template_feed_page.sql")
        async with self._db.session() as session:
            rows = (
                (
                    await session.execute(
                        text(sql),
                        {
                            "video_gym_id": video_gym_id,
                            "status": status.value,
                            "video_type": (
                                video_type.value
                                if video_type is not None
                                else None
                            ),
                            "filter_big_group": (
                                big_group.value
                                if big_group is not None
                                else None
                            ),
                            "educational_genres": educational_genres,
                            "limit": limit,
                            "offset": offset,
                        },
                    )
                )
                .mappings()
                .all()
            )
        return build_feed_page_result(rows)
