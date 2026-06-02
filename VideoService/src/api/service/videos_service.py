"""VideosService — the SQL read path behind the API.

Reads the shared Supabase Postgres (the ``video_*`` tables) via the
``DirectDatabasePool`` + externalised ``.sql`` files. It keeps the exact public
methods and return types the routers / viewer / avatar fallback depend on
(``Gym``, ``VideoOutput``, ``GymsPage``), so only the data *source* changed — not
the API contract. All writes live in the pipeline scripts (scrape / scan /
sync-gyms / import), never here; this module is read-only.
"""

from __future__ import annotations

import json
from collections.abc import Iterable
from pathlib import Path

from sqlalchemy import text

from schema import Gym, GymCard, GymsPage, GymType, VideoOutput
from schema.parent_gym_type import parent_of
from src.api.config import settings
from src.api.errors import NotFoundError
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

SQL_DIR = Path(__file__).resolve().parent.parent / "sql"

# A gym's card art is its theme's celebration image. DERIVED from the gym's
# theme: an absolute CDN URL by default (`assets_cdn_base_url` defaults to the
# prod CDN), or — when that setting is emptied for local dev — a ThemeService-
# relative path the client absolutises. The CDN object key mirrors ThemeService's
# scheme (themes/<app>/<theme>/images/<slot>.png); no `?v=` here — the styles
# catalog's versioned URL is what clients prefer, so this is only the fallback.
THEME_SERVICE_APP_ID = "combatden"
CELEBRATION_SLOT = "celebration_image"
CELEBRATION_IMAGE_URL_TEMPLATE = (
    "/apps/" + THEME_SERVICE_APP_ID + "/{theme}/images/celebration_image"
)


def _celebration_image_url(theme: str) -> str:
    """The gym card's celebration-image URL: absolute CDN when configured, else
    the ThemeService-relative path the client absolutises."""
    base = settings.assets_cdn_base_url
    if base:
        return (
            f"{base.rstrip('/')}/themes/{THEME_SERVICE_APP_ID}"
            f"/{theme}/images/{CELEBRATION_SLOT}.png"
        )
    return CELEBRATION_IMAGE_URL_TEMPLATE.format(theme=theme)


def _as_list(value: object) -> list:
    """A JSONB column as a Python list — tolerant of the driver returning either
    a decoded list or the raw JSON string."""
    if value is None:
        return []
    if isinstance(value, str):
        return json.loads(value)
    return value  # already decoded by the driver


class VideosService:
    """The SQL-backed read store: gyms, their feeds, and the shared video pool."""

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db = db_pool

    # --- gyms ----------------------------------------------------------------

    async def list_gyms(self) -> list[str]:
        """Every gym id, sorted."""
        sql = load_sql(SQL_DIR / "list_gym_ids.sql")
        async with self._db.session() as session:
            rows = (await session.execute(text(sql))).mappings().all()
        return [r["gym_id"] for r in rows]

    async def load_gym(self, gym_id: str) -> Gym:
        """One gym by id, assembled in a single query. Missing -> ``NotFoundError``."""
        sql = load_sql(SQL_DIR / "load_gym.sql")
        async with self._db.session() as session:
            row = (
                await session.execute(text(sql), {"gym_id": gym_id})
            ).mappings().fetchone()
        if row is None:
            raise NotFoundError(f"no gym {gym_id!r}")
        return self._row_to_gym(row)

    @staticmethod
    def _row_to_gym(row: object) -> Gym:
        """Build a ``Gym`` from a ``load_gym.sql`` row. ``has_classes`` /
        ``has_rewards`` distinguish "absent" (None) from "authored but empty"."""
        return Gym.model_validate(
            {
                "gym_id": row["gym_id"],
                "gym_type": _as_list(row["gym_type"]),
                "theme": row["theme"],
                "videos": {
                    "specification": {
                        "short_videos_desc": row["short_videos_desc"],
                        "short_avoid_desc": row["short_avoid_desc"],
                        "videos_desc": row["videos_desc"],
                        "avoid_desc": row["avoid_desc"],
                    },
                    "queries": _as_list(row["queries"]),
                    "good_video_ids": _as_list(row["good_video_ids"]),
                    "rejected_video_ids": _as_list(row["rejected_video_ids"]),
                },
                "classes": _as_list(row["classes"]) if row["has_classes"] else None,
                "rewards": _as_list(row["rewards"]) if row["has_rewards"] else None,
            }
        )

    async def list_gyms_page(
        self, *, limit: int, offset: int, query: str | None = None
    ) -> GymsPage:
        """One page of slim gym cards, sorted by gym id. ``query`` is an optional
        case-insensitive substring filter on gym id / theme / discipline. Filtered
        and paginated in Python (only ~76 gyms), matching the prior behaviour."""
        sql = load_sql(SQL_DIR / "list_gym_cards.sql")
        async with self._db.session() as session:
            rows = (await session.execute(text(sql))).mappings().all()
        items = [(r, _as_list(r["gym_type"])) for r in rows]
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
            GymCard(
                gym_id=r["gym_id"],
                gym_type=disc,
                parent_gym_type=parent_of(GymType(disc[0])),
                theme=r["theme"],
                celebration_image_url=_celebration_image_url(r["theme"]),
                video_count=r["video_count"],
                has_classes=r["has_classes"],
                has_rewards=r["has_rewards"],
            )
            for (r, disc) in items[offset : offset + limit]
        ]
        return GymsPage(total=total, limit=limit, offset=offset, gyms=cards)

    # --- the shared video pool ----------------------------------------------

    async def load_videos(self, video_ids: list[str]) -> list[VideoOutput]:
        """Load the given pooled videos by id, preserving the given order and
        skipping any id with no row (so a feed costs O(feed size))."""
        by_id = await self.load_videos_by_id(video_ids)
        return [by_id[v] for v in video_ids if v in by_id]

    async def load_videos_by_id(
        self, ids: Iterable[str]
    ) -> dict[str, VideoOutput]:
        """Load ONLY the named pooled videos, keyed by id. A row that fails to
        validate is skipped (the card just won't show), matching the prior
        tolerant behaviour."""
        wanted = list(dict.fromkeys(ids))
        if not wanted:
            return {}
        sql = load_sql(SQL_DIR / "load_videos.sql")
        async with self._db.session() as session:
            rows = (
                await session.execute(text(sql), {"ids": wanted})
            ).mappings().all()
        out: dict[str, VideoOutput] = {}
        for row in rows:
            data = dict(row)
            video_id = data.pop("video_id")
            data["gym_type"] = _as_list(data.get("gym_type"))
            data["source_queries"] = _as_list(data.get("source_queries"))
            try:
                out[video_id] = VideoOutput.model_validate(data)
            except ValueError:
                continue  # malformed row -> omit, as the YAML path did
        return out


# Process-scoped singleton the routers depend on. Built lazily on first call so
# tests can assign a stub to ``_DEFAULT`` before first use without ever opening a
# real connection.
_DEFAULT: VideosService | None = None
_POOL: DirectDatabasePool | None = None


def videos_service() -> VideosService:
    """The one process-scoped VideosService, lazily built on first call (which
    opens the DB pool). Assign a stub to ``_DEFAULT`` in tests to avoid the DB."""
    global _DEFAULT, _POOL
    if _DEFAULT is None:
        _POOL = DirectDatabasePool()
        _DEFAULT = VideosService(_POOL)
    return _DEFAULT
