"""VideosService — the SQL read path behind the videos domain.

Reads the shared Supabase Postgres via the ``DirectDatabasePool`` +
externalised ``.sql`` files. Two surfaces, both read-only:

* the slug-keyed ``video_gym*`` template catalog (cards + one template's detail),
* a real gym's live content from the UUID-keyed ``gym_video_*`` tables (the served
  feed ids, hydrated from the shared ``video`` pool, plus the gym's spec and its
  ``gym_classes`` / ``gym_rewards`` showcase).

All writes (scrape / scan / sync / preset import) live elsewhere; this is
read-only. This is a DI-provider service (constructed via
``DependencyInjector.videos_service``) — no module-level singleton.
"""

from __future__ import annotations

import json
from collections.abc import Iterable
from uuid import UUID

from sqlalchemy import text

from src.core.config import settings
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql
from src.videos import SQL_DIR
from src.videos.schema.videos_gym_type import GymType
from src.videos.schema.videos_parent_gym_type import parent_of
from src.videos.schema.videos_schema import (
    GymVideoCard,
    GymVideoSpecView,
    ShowcaseClassCard,
    ShowcaseRewardCard,
    VideoTemplateCard,
    VideoTemplateCatalogPage,
    VideoTemplateClassCard,
    VideoTemplateDetail,
    VideoTemplateRewardCard,
    VideoTemplateSpecView,
)

# A template's card art is its theme's celebration image. DERIVED from the
# theme: an absolute CDN URL by default (``video_assets_cdn_base_url`` defaults
# to the prod CDN), or — when that setting is emptied for local dev — a
# ThemeService-relative path the client absolutises. The CDN object key mirrors
# ThemeService's scheme (themes/<app>/<theme>/images/<slot>.png).
_CELEBRATION_SLOT = "celebration_image"


class VideosService:
    """The SQL-backed read store: video templates, a gym's feed + showcase."""

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
        return value  # already decoded by the driver

    @staticmethod
    def _celebration_image_url(theme: str) -> str:
        """The template card's celebration-image URL: absolute CDN when
        configured, else the ThemeService-relative path the client
        absolutises."""
        base = settings.video_assets_cdn_base_url
        app_id = settings.video_app_id
        if base:
            return (
                f"{base.rstrip('/')}/themes/{app_id}"
                f"/{theme}/images/{_CELEBRATION_SLOT}.png"
            )
        return f"/apps/{app_id}/{theme}/images/{_CELEBRATION_SLOT}"

    @staticmethod
    def _instructor_name(
        first_name: str | None, last_name: str | None
    ) -> str | None:
        """A class instructor's display name from first/last (null-safe). None
        when neither part is present."""
        parts = [p for p in (first_name, last_name) if p]
        return " ".join(parts) if parts else None

    # ── template catalog (slug-keyed video_gym*) ─────────────────

    async def list_template_cards(
        self, *, limit: int, offset: int, query: str | None = None
    ) -> VideoTemplateCatalogPage:
        """One page of slim template cards, sorted by id. ``query`` is an optional
        case-insensitive substring filter on slug / theme / discipline. Filtered
        and paginated in Python (only ~76 templates)."""
        sql = load_sql(SQL_DIR / "videos_list_template_cards.sql")
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
        cards = [
            VideoTemplateCard(
                video_gym_id=r["gym_id"],
                gym_type=disc,
                parent_gym_type=parent_of(GymType(disc[0])),
                theme=r["theme"],
                celebration_image_url=self._celebration_image_url(r["theme"]),
                video_count=r["video_count"],
                has_classes=r["has_classes"],
                has_rewards=r["has_rewards"],
            )
            for (r, disc) in items[offset : offset + limit]
        ]
        return VideoTemplateCatalogPage(
            total=total, limit=limit, offset=offset, gyms=cards
        )

    async def load_template(
        self, video_gym_id: str
    ) -> VideoTemplateDetail | None:
        """One template's full detail by slug, assembled in a single query.
        Returns None when the template is missing (the router maps that to
        404)."""
        sql = load_sql(SQL_DIR / "videos_load_template.sql")
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

    def _row_to_template(self, row: object) -> VideoTemplateDetail:
        """Build a ``VideoTemplateDetail`` from a ``videos_load_template.sql``
        row. ``has_classes`` / ``has_rewards`` distinguish "absent" (None) from
        "authored but empty"."""
        classes = (
            [
                VideoTemplateClassCard.model_validate(c)
                for c in self._as_list(row["classes"])
            ]
            if row["has_classes"]
            else None
        )
        rewards = (
            [
                VideoTemplateRewardCard.model_validate(r)
                for r in self._as_list(row["rewards"])
            ]
            if row["has_rewards"]
            else None
        )
        return VideoTemplateDetail(
            video_gym_id=row["gym_id"],
            theme=row["theme"],
            specification=VideoTemplateSpecView(
                short_videos_desc=row["short_videos_desc"],
                short_avoid_desc=row["short_avoid_desc"],
                videos_desc=row["videos_desc"],
                avoid_desc=row["avoid_desc"],
            ),
            classes=classes,
            rewards=rewards,
        )

    async def load_template_feed_ids(self, video_gym_id: str) -> list[str]:
        """A template's approved feed ids (slug-keyed), in pool-relevance order.
        Powers the public template feed/preview the gym/theme picker renders."""
        sql = load_sql(SQL_DIR / "videos_load_template_feed_ids.sql")
        async with self._db.session() as session:
            rows = (
                (
                    await session.execute(
                        text(sql), {"video_gym_id": video_gym_id}
                    )
                )
                .mappings()
                .all()
            )
        return [r["video_id"] for r in rows]

    # ── the shared video pool (live feed) ────────────────────────

    async def load_feed_ids(self, gym_id: UUID) -> list[str]:
        """A real gym's served feed ids, in pool-relevance order. Empty when the
        gym serves nothing."""
        sql = load_sql(SQL_DIR / "videos_load_feed_ids.sql")
        async with self._db.session() as session:
            rows = (
                (
                    await session.execute(
                        text(sql), {"gym_id": str(gym_id)}
                    )
                )
                .mappings()
                .all()
            )
        return [r["video_id"] for r in rows]

    async def load_pool_videos(
        self, video_ids: list[str]
    ) -> list[GymVideoCard]:
        """Load the given pooled videos by id, preserving the given order and
        skipping any id with no row (so a feed costs O(feed size))."""
        by_id = await self._load_pool_videos_by_id(video_ids)
        return [by_id[v] for v in video_ids if v in by_id]

    async def _load_pool_videos_by_id(
        self, ids: Iterable[str]
    ) -> dict[str, GymVideoCard]:
        """Load ONLY the named pooled videos, keyed by id. A row that fails to
        validate is skipped (the card just won't show), matching the prior
        tolerant behaviour."""
        wanted = list(dict.fromkeys(ids))
        if not wanted:
            return {}
        sql = load_sql(SQL_DIR / "videos_load_pool_videos.sql")
        async with self._db.session() as session:
            rows = (
                (await session.execute(text(sql), {"ids": wanted}))
                .mappings()
                .all()
            )
        out: dict[str, GymVideoCard] = {}
        for row in rows:
            data = dict(row)
            video_id = data.pop("video_id")
            try:
                out[video_id] = GymVideoCard.model_validate(data)
            except ValueError:
                continue  # malformed row -> omit
        return out

    # ── live gym spec + showcase ─────────────────────────────────

    async def load_gym_spec(self, gym_id: UUID) -> GymVideoSpecView | None:
        """A real gym's live video spec, or None when no spec row exists yet."""
        sql = load_sql(SQL_DIR / "videos_load_gym_spec.sql")
        async with self._db.session() as session:
            row = (
                (
                    await session.execute(
                        text(sql), {"gym_id": str(gym_id)}
                    )
                )
                .mappings()
                .fetchone()
            )
        if row is None:
            return None
        data = dict(row)
        data["gym_type"] = self._as_list(data.get("gym_type"))
        return GymVideoSpecView.model_validate(data)

    async def load_showcase_classes(
        self, gym_id: UUID
    ) -> list[ShowcaseClassCard]:
        """A real gym's active class cards (with resolved instructor) for the
        showcase, in class-name order."""
        sql = load_sql(SQL_DIR / "videos_load_showcase_classes.sql")
        async with self._db.session() as session:
            rows = (
                (
                    await session.execute(
                        text(sql), {"gym_id": str(gym_id)}
                    )
                )
                .mappings()
                .all()
            )
        return [
            ShowcaseClassCard(
                name=r["name"],
                image_url=r["image_url"],
                description=r["description"],
                instructor_name=self._instructor_name(
                    r["first_name"], r["last_name"]
                ),
                instructor_bio=r["instructor_bio"],
                instructor_image_url=r["instructor_image_url"],
            )
            for r in rows
        ]

    async def load_showcase_rewards(
        self, gym_id: UUID
    ) -> list[ShowcaseRewardCard]:
        """A real gym's active reward cards for the showcase, in points order."""
        sql = load_sql(SQL_DIR / "videos_load_showcase_rewards.sql")
        async with self._db.session() as session:
            rows = (
                (
                    await session.execute(
                        text(sql), {"gym_id": str(gym_id)}
                    )
                )
                .mappings()
                .all()
            )
        return [ShowcaseRewardCard.model_validate(dict(r)) for r in rows]
