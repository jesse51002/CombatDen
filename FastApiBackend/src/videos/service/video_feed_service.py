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
from src.videos.schema.videos_big_group import EDUCATIONAL_GENRES, BigGroup
from src.videos.schema.videos_schema import (
    GymFeedSection,
    GymVideoCard,
    YouTubeVideoMetadata,
    build_feed_page_result,
)
from src.videos.service.member_video_profile_service import (
    MemberVideoProfileService,
)
from src.videos.service.youtube_metadata import YouTubeMetadataClient

# Half-life days → seconds for the watch penalty decay (config carries days).
SECONDS_PER_DAY = 86400

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
        bump_sigma_fraction: float,
        watch_penalty_half_life_days: float,
    ) -> None:
        self._db = db_pool
        self._youtube = youtube_client
        self._profiles = profile_service
        self._bump_fraction = bump_sigma_fraction
        self._half_life_seconds = watch_penalty_half_life_days * SECONDS_PER_DAY

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

    # ── feed reads ────────────────────────────────────────────────

    async def load_feed_preview(
        self, gym_id: UUID, *, per_tag: int, rejected: bool = False
    ) -> list[GymFeedSection]:
        """The "All" preview — up to ``per_tag`` videos per genre in one query.

        Runs the same served candidate set as the feed page (shared
        ``videos_feed_candidate_source.sql``), restricted to tagged videos and
        windowed per genre (``ROW_NUMBER() … WHERE rn <= :per_tag``) so no genre
        is starved and the whole feed is never loaded to slice in Python.
        ``rejected=True`` previews the rejected list. Sections come back in
        first-appearance (feed) order; untagged videos form no section.
        """
        scan_status = (
            GymVideoScanStatus.rejected
            if rejected
            else GymVideoScanStatus.accepted
        )
        candidate_source = load_sql(
            SQL_DIR / "videos_feed_candidate_source.sql"
        )
        sql = load_sql(
            SQL_DIR / "videos_load_feed_preview.sql",
            {"candidate_source": candidate_source},
        )
        params = {
            "gym_id": str(gym_id),
            "scan_status": scan_status.value,
            "per_tag": per_tag,
        }
        async with self._db.session() as session:
            rows = (
                (await session.execute(text(sql), params)).mappings().all()
            )
        return self._build_preview_sections(rows)

    @staticmethod
    def _build_preview_sections(rows: list) -> list[GymFeedSection]:
        """Group the ordered preview rows into one section per genre.

        The SQL orders rows so each genre's rows are contiguous and in
        first-appearance (feed) order, so a single pass preserving first-seen
        order rebuilds the sections. A row that fails ``GymVideoCard`` validation
        is skipped (one bad row never breaks the preview)."""
        order: list[VideoGenre] = []
        by_tag: dict[VideoGenre, list[GymVideoCard]] = {}
        for row in rows:
            try:
                card = GymVideoCard.model_validate(dict(row))
            except ValueError:
                continue
            if card.tag is None:  # defensive — the SQL already excludes these
                continue
            if card.tag not in by_tag:
                by_tag[card.tag] = []
                order.append(card.tag)
            by_tag[card.tag].append(card)
        return [GymFeedSection(tag=t, videos=by_tag[t]) for t in order]

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
        rejected: bool = False,
        video_type: VideoGenre | None = None,
        big_group: BigGroup | None = None,
        member_id: UUID | None = None,
        limit: int,
        offset: int,
    ) -> tuple[list[GymVideoCard], int]:
        """THE unified real-gym feed page — one query for the whole feed.

        ALWAYS merges the owner "Your videos" section with the gym's latest
        COMPLETED run (no owner/source param), serves ONLY enriched-AND-accepted
        videos (INNER JOIN ``video_rag``), and ranks on a single axis with a
        σ-scaled owner boost + a decayed already-watched penalty. Returns
        ``(page, total)`` in one round-trip.

        The rank axis is cosine distance to the member's video-taste embedding
        when ``member_id`` is supplied AND that member has a built embedding, else
        gym ``relevance_index``. Passing a ``member_id`` first verifies that
        member belongs to ``gym_id`` (``MemberNotInGymError`` → 404 otherwise) in
        the SAME row read that loads the embedding, so a member_id not in the path
        gym can never rank a DIFFERENT gym's feed (symmetric with the rec path).
        The embedding is READ-ONLY (never built here); ``member_id`` is only a
        ranking hint — the candidate set is always this gym's feed, so it can't
        leak (the route is already gym-employee gated). The per-member decayed
        watch penalty (from ``member_video_recs``) is what advances the rec on a
        re-serve; it is 0 when ``member_id`` is None.

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
            await self._profiles.verify_and_load_embedding(member_id, gym_id)
            if member_id is not None
            else None
        )
        params: dict = {
            "gym_id": str(gym_id),
            "scan_status": scan_status.value,
            "video_type": (
                video_type.value if video_type is not None else None
            ),
            "filter_big_group": (
                big_group.value if big_group is not None else None
            ),
            "educational_genres": educational_genres,
            "member_embedding": embedding,
            "member_id": str(member_id) if member_id is not None else None,
            "bump_fraction": self._bump_fraction,
            "half_life_seconds": self._half_life_seconds,
            "limit": limit,
            "offset": offset,
        }
        candidate_source = load_sql(
            SQL_DIR / "videos_feed_candidate_source.sql"
        )
        sql = load_sql(
            SQL_DIR / "videos_load_feed_page.sql",
            {"candidate_source": candidate_source},
        )
        async with self._db.session() as session:
            rows = (
                (await session.execute(text(sql), params)).mappings().all()
            )
        return build_feed_page_result(rows)

    async def load_owner_videos(
        self, gym_id: UUID, *, limit: int, offset: int
    ) -> tuple[list[GymVideoCard], int]:
        """The gym owner's UNGATED "Your videos" management listing.

        Unlike the served feed, this is NOT enriched-gated: an owner-added video
        shows the instant it's added (before enrichment). Owner-section rows only
        (``video_run_id IS NULL``), accepted, newest add first; each card carries
        ``enriched`` (LEFT JOIN ``video_rag``) so the CRM can badge "processing…".
        """
        sql = load_sql(SQL_DIR / "videos_load_owner_videos.sql")
        params = {"gym_id": str(gym_id), "limit": limit, "offset": offset}
        async with self._db.session() as session:
            rows = (
                (await session.execute(text(sql), params)).mappings().all()
            )
        return build_feed_page_result(rows)

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
            video_id = data["video_id"]
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
            video_id=video_id,
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
            owner_added=True,
            enriched=False,
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
        # It was just added to the owner section — flag it so (the pool read
        # doesn't carry the owner-section membership). enriched=False: it has no
        # video_rag row yet, so it won't surface in the member feed until the
        # worker's enrich sweep reaches it (the owner listing shows it meanwhile).
        return cards[0].model_copy(update={"owner_added": True, "enriched": False})

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
