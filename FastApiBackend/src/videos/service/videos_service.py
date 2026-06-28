"""VideosService — the SQL read path (plus owner feed edits) for the videos
domain.

Reads the shared Supabase Postgres via the ``DirectDatabasePool`` +
externalised ``.sql`` files. Two read surfaces:

* the slug-keyed ``video_gym*`` template catalog (cards + one template's detail),
* a real gym's live content from the UUID-keyed ``gym_video_*`` tables (the served
  feed ids, hydrated from the shared ``video`` pool, plus the gym's spec and its
  ``gym_classes`` / ``gym_rewards`` showcase).

It also owns the hand-edits a gym makes to its own feed: adding a single YouTube
link (``add_feed_video`` — fetches the video's real metadata from the YouTube
Data API) and removing one (``remove_feed_video`` — deletes the feed row AND
appends a reasoned audit to ``gym_video_feed_removal``). The bulk writes (scrape
/ scan / sync / preset import) still live elsewhere. This is a DI-provider
service (constructed via ``DependencyInjector.videos_service``) — no
module-level singleton.
"""

from __future__ import annotations

import json
import re
from collections.abc import Iterable
from urllib.parse import parse_qs, urlparse
from uuid import UUID

from schema.video import GymVideoScanStatus, VideoGymFeedStatus, VideoSource
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
from src.videos.service.youtube_metadata import YouTubeMetadataClient

# A template's card art is its theme's celebration image. DERIVED from the
# theme: an absolute CDN URL by default (``video_assets_cdn_base_url`` defaults
# to the prod CDN), or — when that setting is emptied for local dev — a
# ThemeService-relative path the client absolutises. The CDN object key mirrors
# ThemeService's scheme (themes/<app>/<theme>/images/<slot>.png).
_CELEBRATION_SLOT = "celebration_image"

# ── Owner-added video (store-URL-only) ───────────────────────────────
# A YouTube video id is always 11 chars from this alphabet. We extract + validate
# against it so a garbage / non-YouTube URL is rejected (400) rather than stored.
_YOUTUBE_ID_RE = re.compile(r"^[A-Za-z0-9_-]{11}$")
_YOUTUBE_HOSTS = frozenset(
    {"youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be"}
)
# Path-style links carry the id as the segment after one of these prefixes
# (``/embed/<id>``, ``/shorts/<id>``, ``/v/<id>``, ``/live/<id>``).
_YOUTUBE_PATH_PREFIXES = frozenset({"embed", "shorts", "v", "live"})
# The canonical row we store for an owner-added video (no metadata fetch).
_YOUTUBE_WATCH_URL = "https://www.youtube.com/watch?v={video_id}"
_YOUTUBE_THUMBNAIL_URL = "https://img.youtube.com/vi/{video_id}/hqdefault.jpg"


class VideosService:
    """The SQL-backed read store: video templates, a gym's feed + showcase."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        youtube_client: YouTubeMetadataClient,
    ) -> None:
        self._db = db_pool
        self._youtube = youtube_client

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

    @staticmethod
    def _extract_youtube_id(url: str) -> str:
        """Extract the 11-char YouTube video id from an owner-pasted link.

        Handles ``watch?v=``, ``youtu.be/<id>``, ``/embed/<id>``,
        ``/shorts/<id>``, ``/v/<id>``, ``/live/<id>``, and a bare id. Raises
        ``ValueError`` for an empty, non-YouTube, or unparseable URL (the router
        maps that to 400).
        """
        raw = (url or "").strip()
        if not raw:
            raise ValueError("empty video URL")
        # A bare id pasted on its own.
        if _YOUTUBE_ID_RE.match(raw):
            return raw
        parsed = urlparse(raw if "//" in raw else f"https://{raw}")
        host = (parsed.hostname or "").lower()
        if host not in _YOUTUBE_HOSTS:
            raise ValueError(f"not a YouTube URL: {url!r}")
        if host == "youtu.be":
            candidate = parsed.path.lstrip("/").split("/", 1)[0]
        elif parsed.path == "/watch":
            values = parse_qs(parsed.query).get("v")
            candidate = values[0] if values else None
        else:
            parts = [p for p in parsed.path.split("/") if p]
            candidate = (
                parts[1]
                if len(parts) >= 2 and parts[0] in _YOUTUBE_PATH_PREFIXES
                else None
            )
        if not candidate or not _YOUTUBE_ID_RE.match(candidate):
            raise ValueError(f"could not extract a YouTube id from {url!r}")
        return candidate

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

    async def load_template_feed_ids(
        self, video_gym_id: str, *, rejected: bool = False
    ) -> list[str]:
        """A template's feed ids (slug-keyed), in pool-relevance order. Serves the
        approved feed by default, or the scan's rejected list when ``rejected``.
        Powers the public template feed/preview the gym/theme picker renders."""
        status = (
            VideoGymFeedStatus.rejected if rejected else VideoGymFeedStatus.good
        )
        sql = load_sql(SQL_DIR / "videos_load_template_feed_ids.sql")
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

    # ── the shared video pool (live feed) ────────────────────────

    async def load_feed_ids(
        self, gym_id: UUID, *, owner: bool = False, rejected: bool = False
    ) -> list[str]:
        """A real gym's feed ids, in pool-relevance order. ``owner=True`` returns
        the owner "Your videos" section (run-independent); ``False`` the gym's
        latest scan run. ``rejected=True`` returns the rejected list instead of
        the served (accepted) videos."""
        scan_status = (
            GymVideoScanStatus.rejected
            if rejected
            else GymVideoScanStatus.accepted
        )
        sql = load_sql(SQL_DIR / "videos_load_feed_ids.sql")
        async with self._db.session() as session:
            rows = (
                (
                    await session.execute(
                        text(sql),
                        {
                            "gym_id": str(gym_id),
                            "owner": owner,
                            "scan_status": scan_status.value,
                        },
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

    # ── owner feed edits (add / remove a single video) ───────────

    async def lookup_feed_video(self, url: str) -> GymVideoCard:
        """Fetch a YouTube link's real metadata and return it as a card, WITHOUT
        writing anything. Powers the "confirm these details before adding"
        preview. The card is raw — the router applies the same channel-avatar
        backfill as the feed.

        Raises:
            ValueError: ``url`` isn't a recognisable YouTube link (router → 400).
            YouTubeVideoNotFoundError: the id resolved to no video (router → 400).
            YouTubeApiError: the YouTube Data API call failed (router → 502).
        """
        video_id = self._extract_youtube_id(url)
        metadata = await self._youtube.fetch(video_id)
        return GymVideoCard(
            url=_YOUTUBE_WATCH_URL.format(video_id=video_id),
            title=metadata.title,
            thumbnail_url=metadata.thumbnail_url
            or _YOUTUBE_THUMBNAIL_URL.format(video_id=video_id),
            channel_name=metadata.channel_name,
            channel_url=metadata.channel_url,
            channel_avatar_url=metadata.channel_avatar_url,
            view_count=metadata.view_count,
            duration_seconds=metadata.duration_seconds,
            relevance_index=0,
            tag=None,
        )

    async def add_feed_video(self, gym_id: UUID, url: str) -> GymVideoCard:
        """Add one owner-provided YouTube video to the gym's served feed.

        Fetches the video's real metadata (title / channel / thumbnail / views /
        duration / channel avatar) from the YouTube Data API, then upserts the
        pool row (a brand-new row is OWNED by this gym — ``gym_id`` set, a private
        custom video; on conflict it refreshes metadata only when the existing row
        is metadata-less and never touches ``gym_id``, so adding an already-shared
        video leaves it shared) and adds the feed membership, both in one
        transaction. Returns the resulting :class:`GymVideoCard` (raw — the router
        applies the same channel-avatar backfill as the feed).

        Raises:
            ValueError: ``url`` isn't a recognisable YouTube link (router → 400).
            YouTubeVideoNotFoundError: the id resolved to no video (router → 400).
            YouTubeApiError: the YouTube Data API call failed (router → 502).
        """
        video_id = self._extract_youtube_id(url)
        metadata = await self._youtube.fetch(video_id)
        upsert_sql = load_sql(SQL_DIR / "videos_upsert_pool_video.sql")
        insert_feed_sql = load_sql(SQL_DIR / "videos_insert_feed_video.sql")
        params = {
            "video_id": video_id,
            "url": _YOUTUBE_WATCH_URL.format(video_id=video_id),
            "title": metadata.title,
            # Fall back to the derived thumbnail only if the API returned none.
            "thumbnail_url": metadata.thumbnail_url
            or _YOUTUBE_THUMBNAIL_URL.format(video_id=video_id),
            "channel_name": metadata.channel_name,
            "channel_url": metadata.channel_url,
            "channel_avatar_url": metadata.channel_avatar_url,
            "view_count": metadata.view_count,
            "duration_seconds": metadata.duration_seconds,
            # A new owner-added video is owned by this gym (a private custom row).
            "gym_id": str(gym_id),
        }
        async with self._db.session() as session, session.begin():
            await session.execute(text(upsert_sql), params)
            await session.execute(
                text(insert_feed_sql),
                {"gym_id": str(gym_id), "video_id": video_id},
            )
        cards = await self.load_pool_videos([video_id])
        if not cards:
            # Unreachable — we just upserted the pool row in the same call.
            raise RuntimeError(
                f"pool video {video_id!r} missing immediately after insert"
            )
        return cards[0]

    async def remove_feed_video(
        self,
        gym_id: UUID,
        video_id: str,
        *,
        owner: bool = False,
        reason: str | None = None,
    ) -> None:
        """Remove one video — behaviour set by the SECTION it's removed from:

        * **owner=True** ("Your videos"): DELETE the owner-section feed row (take
          it out of the gym's own section). If the video is a manual, gym-owned
          custom video, also delete its owned pool row.
        * **owner=False** (a genre / latest-run video): REJECT it — flip the
          latest-run row to ``scan_status='rejected'`` with
          ``rejection_type='manual'`` + the optional ``reason`` (kept; "keep" can
          flip it back).

        Idempotent: a no-op when the video isn't in that section.
        """
        params = {"gym_id": str(gym_id), "video_id": video_id}
        async with self._db.session() as session, session.begin():
            if owner:
                await session.execute(
                    text(load_sql(SQL_DIR / "videos_delete_feed_video.sql")),
                    params,
                )
                source = (
                    await session.execute(
                        text(load_sql(SQL_DIR / "videos_get_video_source.sql")),
                        {"video_id": video_id},
                    )
                ).scalar()
                if source == VideoSource.manual.value:
                    await session.execute(
                        text(
                            load_sql(
                                SQL_DIR / "videos_delete_owned_pool_video.sql"
                            )
                        ),
                        params,
                    )
            else:
                await session.execute(
                    text(load_sql(SQL_DIR / "videos_reject_feed_video.sql")),
                    {**params, "reason": reason},
                )

    async def keep_feed_video(self, gym_id: UUID, video_id: str) -> None:
        """"Keep" a rejected video: flip its served row(s) back to accepted,
        leaving the reject audit intact as history."""
        keep_sql = load_sql(SQL_DIR / "videos_keep_feed_video.sql")
        async with self._db.session() as session, session.begin():
            await session.execute(
                text(keep_sql),
                {"gym_id": str(gym_id), "video_id": video_id},
            )
