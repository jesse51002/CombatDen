"""WorkerAvatarResolver — no DB, no network.

Covers the scrape's creator-avatar pass: ≤50 channel ids per ``channels.list``
call at 1 quota unit each, uncovered-first ordering under the per-run cap, the
per-channel (not per-video) write fan-out, and the degrade-never-crash posture on
a 403/quota error.
"""

from __future__ import annotations

import asyncio

from schema.video_output import VideoOutput
from src.worker.worker_avatars import WorkerAvatarResolver
from src.worker.worker_config import settings
from src.worker.worker_transforms import CHANNEL_URL
from src.worker.worker_youtube import MAX_PAGE_SIZE
from tests.worker_fakes import FakeYouTube, RoutingFakeDb


def _video(vid: str, channel_id: str) -> VideoOutput:
    return VideoOutput(
        url=f"https://www.youtube.com/watch?v={vid}",
        title=f"Video {vid}",
        description="",
        thumbnail_url="https://i.ytimg.com/x.jpg",
        channel_name="Chan",
        channel_url=CHANNEL_URL.format(channel_id=channel_id),
        channel_avatar_url="",
        view_count=1,
        like_count=1,
        duration_seconds=60,
        source_queries=["q"],
        relevance_index=0,
        transcript=None,
    )


def _channel(cid: str) -> dict:
    return {
        "id": cid,
        "snippet": {"thumbnails": {"high": {"url": f"https://yt3.ggpht.com/{cid}"}}},
    }


def _resolver(db: RoutingFakeDb, youtube: FakeYouTube) -> WorkerAvatarResolver:
    return WorkerAvatarResolver(db, youtube)


def _avatar_writes(db: RoutingFakeDb) -> list[dict]:
    return [
        row
        for name, _, params in db.writes
        if name == "update_channel_avatar"
        for row in params
    ]


def test_resolves_distinct_channels_and_writes_by_channel_url() -> None:
    db = RoutingFakeDb()
    youtube = FakeYouTube(channels={"UCa": _channel("UCa"), "UCb": _channel("UCb")})
    # Three videos, two channels — the API is asked about CHANNELS, not videos.
    videos = [_video("v1", "UCa"), _video("v2", "UCa"), _video("v3", "UCb")]

    result = asyncio.run(_resolver(db, youtube).refresh_for_scrape(videos))

    assert youtube.channels_listed == [["UCa", "UCb"]]
    assert result.channels_seen == 2
    assert result.channels_resolved == 2
    assert result.quota_units == 1  # one channels.list call
    assert _avatar_writes(db) == [
        {
            "channel_url": CHANNEL_URL.format(channel_id="UCa"),
            "channel_avatar_url": "https://yt3.ggpht.com/UCa",
        },
        {
            "channel_url": CHANNEL_URL.format(channel_id="UCb"),
            "channel_avatar_url": "https://yt3.ggpht.com/UCb",
        },
    ]


def test_no_resolvable_channels_is_a_noop() -> None:
    db = RoutingFakeDb()
    youtube = FakeYouTube()
    # A video whose snippet had no channelId leaves channel_url empty.
    videos = [_video("v1", "UCa")]
    videos[0] = videos[0].model_copy(update={"channel_url": ""})

    result = asyncio.run(_resolver(db, youtube).refresh_for_scrape(videos))

    assert result.channels_seen == 0
    assert youtube.channels_listed == []
    assert db.writes == []


def test_batches_at_fifty_and_charges_one_unit_each() -> None:
    db = RoutingFakeDb()
    ids = [f"UC{i:03d}" for i in range(MAX_PAGE_SIZE + 5)]
    youtube = FakeYouTube(channels={cid: _channel(cid) for cid in ids})

    avatars, quota_units = asyncio.run(_resolver(db, youtube).resolve(ids))

    assert [len(batch) for batch in youtube.channels_listed] == [MAX_PAGE_SIZE, 5]
    assert quota_units == 2  # 1 unit per CALL, not per id
    assert len(avatars) == len(ids)


def test_one_failing_batch_is_dropped_not_raised() -> None:
    db = RoutingFakeDb()
    ids = [f"UC{i:03d}" for i in range(MAX_PAGE_SIZE + 2)]

    class BoomFirstBatch(FakeYouTube):
        async def list_channels(self, channel_ids):  # noqa: ANN001
            self.channels_listed.append(list(channel_ids))
            if len(self.channels_listed) == 1:
                raise RuntimeError("403 quotaExceeded")
            return [_channel(c) for c in channel_ids]

    avatars, quota_units = asyncio.run(_resolver(db, BoomFirstBatch()).resolve(ids))

    # The second batch still ran and its avatars survived.
    assert set(avatars) == set(ids[MAX_PAGE_SIZE:])
    # Both attempts are charged: a 403 still consumed the call.
    assert quota_units == 2


def test_uncovered_channels_are_resolved_before_the_cap_binds(monkeypatch) -> None:  # noqa: ANN001
    """When the per-run cap binds, a channel with NO avatar must beat a refresh."""
    db = RoutingFakeDb()
    covered = CHANNEL_URL.format(channel_id="UCold")
    db.rows["channel_avatar_state"] = [
        {"channel_url": covered, "has_avatar": True},
    ]
    youtube = FakeYouTube(channels={"UCnew": _channel("UCnew")})
    # Cap the pass at ONE channel so the ordering is what decides.
    monkeypatch.setattr(settings, "worker_avatar_max_batches", 1)
    monkeypatch.setattr("src.worker.worker_avatars.MAX_PAGE_SIZE", 1)

    result = asyncio.run(
        _resolver(db, youtube).refresh_for_scrape(
            [_video("v1", "UCold"), _video("v2", "UCnew")]
        )
    )

    assert youtube.channels_listed == [["UCnew"]]  # the uncovered one won
    assert result.channels_seen == 2 and result.channels_requested == 1


def test_store_skips_empty_avatars() -> None:
    db = RoutingFakeDb()
    written = asyncio.run(
        _resolver(db, FakeYouTube()).store({"UCa": "https://yt3/a", "UCb": ""})
    )
    assert written == 1
    assert _avatar_writes(db) == [
        {
            "channel_url": CHANNEL_URL.format(channel_id="UCa"),
            "channel_avatar_url": "https://yt3/a",
        }
    ]


def test_store_by_url_is_the_single_write_path() -> None:
    """The backfill reuses this, so it must accept stored channel_urls directly."""
    db = RoutingFakeDb()
    url = CHANNEL_URL.format(channel_id="UCa")

    written = asyncio.run(_resolver(db, FakeYouTube()).store_by_url({url: "a.jpg"}))

    assert written == 1
    assert _avatar_writes(db) == [
        {"channel_url": url, "channel_avatar_url": "a.jpg"}
    ]
