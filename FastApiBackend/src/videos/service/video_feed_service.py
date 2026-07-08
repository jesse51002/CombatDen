"""VideoFeedService — a real gym's live video feed + owner edits.

Owns the served feed id reads (scan-run vs. owner section, accepted vs.
rejected), the shared pool video hydration, the add / remove / keep owner
edits, and the YouTube-link preview (lookup). Uses the ``DirectDatabasePool``
+ externalised ``.sql`` files; the YouTube add path calls ``YouTubeMetadataClient``
for real metadata.

This is a concern service composed by the ``VideosService`` facade — it is
not injected directly into the router.
"""

from __future__ import annotations

import re
from collections.abc import Iterable
from urllib.parse import parse_qs, urlparse
from uuid import UUID

from schema.video import GymVideoScanStatus, VideoGenre, VideoSource
from sqlalchemy import text

from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql
from src.videos import SQL_DIR
from src.videos.schema.video_recs_schema import RecCandidate
from src.videos.schema.videos_big_group import EDUCATIONAL_GENRES, BigGroup
from src.videos.schema.videos_schema import (
    GymVideoCard,
    YouTubeVideoMetadata,
    build_feed_page_result,
)
from src.videos.service.member_video_profile_service import (
    MemberVideoProfileService,
)
from src.videos.service.youtube_metadata import YouTubeMetadataClient

# A YouTube video id is always 11 chars from this alphabet.
_YOUTUBE_ID_RE = re.compile(r"^[A-Za-z0-9_-]{11}$")
_YOUTUBE_HOSTS = frozenset(
    {"youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be"}
)
# Path-style links carry the id as the segment after one of these prefixes.
_YOUTUBE_PATH_PREFIXES = frozenset({"embed", "shorts", "v", "live"})
_YOUTUBE_WATCH_URL = "https://www.youtube.com/watch?v={video_id}"
_YOUTUBE_THUMBNAIL_URL = "https://img.youtube.com/vi/{video_id}/hqdefault.jpg"


class VideoFeedService:
    """Serves a real gym's live video feed and owns its owner edit operations.

    Read operations: load the feed id list (by scan run or owner section,
    accepted or rejected) and hydrate those ids from the shared pool.
    Write operations: add a single YouTube link (with real metadata),
    remove (reject or delete from owner section), and keep (un-reject).
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        youtube_client: YouTubeMetadataClient,
        profile_service: MemberVideoProfileService,
    ) -> None:
        self._db = db_pool
        self._youtube = youtube_client
        self._profiles = profile_service

    # ── helpers ──────────────────────────────────────────────────

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

    # ── feed id reads ─────────────────────────────────────────────

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

    async def load_feed_page(
        self,
        gym_id: UUID,
        *,
        owner: bool = False,
        rejected: bool = False,
        video_type: VideoGenre | None = None,
        big_group: BigGroup | None = None,
        member_id: UUID | None = None,
        limit: int,
        offset: int,
    ) -> tuple[list[GymVideoCard], int]:
        """Paginated real-gym feed page with in-DB filtering.

        Joins ``gym_video_feed`` → ``video``, applies owner/run + status +
        optional tag filters at the DB level, and returns ``(page, total)``
        in one round-trip.

        When ``member_id`` is supplied AND that member has a built video-taste
        profile embedding, the page is PERSONALIZED — enriched videos are ranked
        by cosine distance to the member's embedding, un-enriched ones falling to
        the end by relevance. The embedding is READ-ONLY (never built here); a
        member with no embedding (or no ``member_id``) gets the default
        relevance-ordered page. ``member_id`` is only a re-ordering hint — the
        candidate set is always this gym's feed — so no ownership guard is needed
        (the route is already gym-employee gated). NOTE: a member-facing route is
        a future concern; this stays staff-facing (CRM preview) for now.

        ``total`` is the count of all matching rows before pagination (via
        ``COUNT(*) OVER()``). It will be 0 when the requested ``offset``
        exceeds the match count — callers should not request pages past the
        ``total`` returned by the first response.
        """
        scan_status = (
            GymVideoScanStatus.rejected
            if rejected
            else GymVideoScanStatus.accepted
        )
        educational_genres = [g.value for g in EDUCATIONAL_GENRES]
        embedding = (
            await self._profiles.load_embedding(member_id)
            if member_id is not None
            else None
        )
        params: dict = {
            "gym_id": str(gym_id),
            "scan_status": scan_status.value,
            "owner": owner,
            "video_type": (
                video_type.value if video_type is not None else None
            ),
            "filter_big_group": (
                big_group.value if big_group is not None else None
            ),
            "educational_genres": educational_genres,
            "limit": limit,
            "offset": offset,
        }
        if embedding is not None:
            sql_file = "videos_load_feed_page_personalized.sql"
            params["member_embedding"] = embedding
        else:
            sql_file = "videos_load_feed_page.sql"
        sql = load_sql(SQL_DIR / sql_file)
        async with self._db.session() as session:
            rows = (
                (await session.execute(text(sql), params)).mappings().all()
            )
        return build_feed_page_result(rows)

    # ── member rec (single pure-cosine pick) ──────────────────────

    async def load_next_rec_video(
        self,
        gym_id: UUID,
        member_id: UUID,
        category: VideoGenre,
        embedding: str | None,
    ) -> RecCandidate | None:
        """The member's next single recommendation in ``category``, or None.

        Ranks the gym's served feed of that genre by PURE cosine similarity to the
        member's video-taste ``embedding`` (gym relevance when ``embedding`` is
        None), excluding already-served videos so each call advances. Returns the
        single top pick as a :class:`RecCandidate` (its ``video_id`` + card), or
        ``None`` when the category yields no candidate.

        The candidate set is the gym's SERVED feed — accepted rows of the latest
        COMPLETED run PLUS the owner section (``video_run_id IS NULL``) — the same
        set the feed serves (NOT the feed page's exclusive owner flag). This is
        why the rec has its own SQL rather than a ``load_feed_page(limit=1)`` call.
        ``embedding`` is passed in (the rec service loads it once and reuses it
        across the category rotation).
        """
        sql = load_sql(SQL_DIR / "videos_load_next_rec.sql")
        params = {
            "gym_id": str(gym_id),
            "member_id": str(member_id),
            "category": category.value,
            "member_embedding": embedding,
        }
        async with self._db.session() as session:
            row = (
                (await session.execute(text(sql), params)).mappings().fetchone()
            )
        if row is None:
            return None
        return RecCandidate(
            video_id=row["video_id"],
            video=GymVideoCard.model_validate(dict(row)),
        )

    async def _load_pool_videos_by_id(
        self, ids: Iterable[str]
    ) -> dict[str, GymVideoCard]:
        """Load ONLY the named pooled videos, keyed by id. A row that fails to
        validate is skipped (the card just won't show)."""
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
                continue
        return out

    # ── owner feed edits ──────────────────────────────────────────

    async def lookup_feed_video(self, url: str) -> GymVideoCard:
        """Fetch a YouTube link's real metadata and return it as a card, WITHOUT
        writing anything. Powers the "confirm these details before adding" preview.

        Raises:
            ValueError: ``url`` isn't a recognisable YouTube link (router → 400).
            YouTubeVideoNotFoundError: the id resolved to no video (router → 400).
            YouTubeApiError: the YouTube Data API call failed (router → 502).
        """
        video_id = self._extract_youtube_id(url)
        metadata: YouTubeVideoMetadata = await self._youtube.fetch(video_id)
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

        Fetches real metadata from the YouTube Data API, upserts the pool row,
        and adds the feed membership in one transaction.

        Raises:
            ValueError: ``url`` isn't a recognisable YouTube link (router → 400).
            YouTubeVideoNotFoundError: the id resolved to no video (router → 400).
            YouTubeApiError: the YouTube Data API call failed (router → 502).
        """
        video_id = self._extract_youtube_id(url)
        metadata: YouTubeVideoMetadata = await self._youtube.fetch(video_id)
        upsert_sql = load_sql(SQL_DIR / "videos_upsert_pool_video.sql")
        insert_feed_sql = load_sql(SQL_DIR / "videos_insert_feed_video.sql")
        params = {
            "video_id": video_id,
            "url": _YOUTUBE_WATCH_URL.format(video_id=video_id),
            "title": metadata.title,
            "thumbnail_url": metadata.thumbnail_url
            or _YOUTUBE_THUMBNAIL_URL.format(video_id=video_id),
            "channel_name": metadata.channel_name,
            "channel_url": metadata.channel_url,
            "channel_avatar_url": metadata.channel_avatar_url,
            "view_count": metadata.view_count,
            "duration_seconds": metadata.duration_seconds,
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
        """Remove one video — behaviour set by the section it's removed from.

        * **owner=True** ("Your videos"): DELETE the owner-section feed row. If
          the video is a manual, gym-owned custom video, also delete its pool row.
        * **owner=False** (genre / latest-run): REJECT it — flip the latest-run
          row to ``scan_status='rejected'`` with ``curation_type='manual'``.

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

    async def keep_feed_video(
        self,
        gym_id: UUID,
        video_id: str,
        *,
        accept_reason: str | None = None,
    ) -> None:
        """"Keep" a rejected video: flip its served row(s) back to accepted.

        ``accept_reason`` is persisted as ``curation_reason`` on the feed row
        so the feed-learning refiner can incorporate why the owner wanted to
        keep the video when it next widens the spec's include criteria. The
        param is named ``accept_reason`` to match the CRM-facing request body
        (``VideoKeepRequest.accept_reason``); the SQL bind maps it to the
        ``curation_reason`` column.
        """
        keep_sql = load_sql(SQL_DIR / "videos_keep_feed_video.sql")
        async with self._db.session() as session, session.begin():
            await session.execute(
                text(keep_sql),
                {
                    "gym_id": str(gym_id),
                    "video_id": video_id,
                    "accept_reason": accept_reason,
                },
            )
