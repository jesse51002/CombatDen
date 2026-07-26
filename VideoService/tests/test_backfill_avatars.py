"""The one-time avatar backfill — no DB, no network, no quota.

Covers the two passes and the properties that make the run safe to hand to the
founder: pass 1 resolves a channel id PER CHANNEL (not per video) and falls back
to another representative when one has been deleted; the id-form URL rewrite is
what removes the legacy handle data; pass 2 copies an avatar a sibling row already
knows without spending quota; ``--limit`` caps the work; and re-running is a no-op
once the table state says there is nothing left (the resume contract).
"""

from __future__ import annotations

import asyncio

from src.worker.worker_avatars import WorkerAvatarResolver
from src.worker.worker_transforms import CHANNEL_URL
from tests.worker_fakes import FakeYouTube, RoutingFakeDb

from scripts.backfill_avatars.run import BackfillAvatarsRunner

HANDLE_A = "https://www.youtube.com/@alpha"
HANDLE_B = "https://www.youtube.com/@bravo"


def _runner(
    db: RoutingFakeDb, youtube: FakeYouTube, limit: int | None = None
) -> BackfillAvatarsRunner:
    return BackfillAvatarsRunner(
        db, youtube, WorkerAvatarResolver(db, youtube), limit=limit
    )


def _detail(video_id: str, channel_id: str) -> dict:
    return {"id": video_id, "snippet": {"channelId": channel_id}}


def _channel(cid: str) -> dict:
    return {
        "id": cid,
        "snippet": {"thumbnails": {"high": {"url": f"https://yt3.ggpht.com/{cid}"}}},
    }


def _params(db: RoutingFakeDb, name: str) -> list[dict]:
    return [row for n, _, params in db.writes if n == name for row in params]


# --- pass 1: handle-form URL → canonical id-form URL ----------------------------


def test_pass1_resolves_one_video_per_channel_and_upgrades_urls() -> None:
    db = RoutingFakeDb()
    db.rows["handle_channels"] = [
        {"channel_url": HANDLE_A, "video_ids": ["a1", "a2"]},
        {"channel_url": HANDLE_B, "video_ids": ["b1"]},
    ]
    youtube = FakeYouTube(
        details={"a1": _detail("a1", "UCalpha"), "b1": _detail("b1", "UCbravo")}
    )

    totals = asyncio.run(_runner(db, youtube).run())

    # ONE videos.list batch, holding one representative per CHANNEL — not one per
    # handle-form row. That is what makes the pass ~231 calls, not ~457.
    assert youtube.listed == [["a1", "b1"]]
    assert _params(db, "update_channel_url") == [
        {
            "handle_url": HANDLE_A,
            "id_form_url": CHANNEL_URL.format(channel_id="UCalpha"),
        },
        {
            "handle_url": HANDLE_B,
            "id_form_url": CHANNEL_URL.format(channel_id="UCbravo"),
        },
    ]
    assert totals.urls_upgraded == 2
    assert totals.urls_unresolved == 0
    assert totals.quota_units == 1  # 1 unit per videos.list call


def test_pass1_falls_back_to_the_next_representative() -> None:
    """A representative video may have been deleted since the scrape."""
    db = RoutingFakeDb()
    db.rows["handle_channels"] = [
        {"channel_url": HANDLE_A, "video_ids": ["gone", "a2", "a3"]}
    ]
    youtube = FakeYouTube(details={"a2": _detail("a2", "UCalpha")})

    totals = asyncio.run(_runner(db, youtube).run())

    assert youtube.listed == [["gone"], ["a2"]]  # round 1, then round 2
    assert _params(db, "update_channel_url") == [
        {
            "handle_url": HANDLE_A,
            "id_form_url": CHANNEL_URL.format(channel_id="UCalpha"),
        }
    ]
    assert totals.urls_upgraded == 1
    assert totals.quota_units == 2  # one call per round


def test_pass1_leaves_a_wholly_unresolvable_channel_alone() -> None:
    db = RoutingFakeDb()
    db.rows["handle_channels"] = [{"channel_url": HANDLE_A, "video_ids": ["gone"]}]
    youtube = FakeYouTube(details={})

    totals = asyncio.run(_runner(db, youtube).run())

    assert "update_channel_url" not in db.write_names()
    assert totals.urls_upgraded == 0
    assert totals.urls_unresolved == 1


def test_pass1_stops_after_consecutive_api_failures() -> None:
    """An exhausted daily quota fails every call — stop rather than hammer it.
    The run is resumable, so the remaining channels are picked up next time."""
    db = RoutingFakeDb()
    db.rows["handle_channels"] = [
        {"channel_url": f"https://www.youtube.com/@c{i}", "video_ids": [f"v{i}"]}
        for i in range(200)
    ]

    class AlwaysBoom(FakeYouTube):
        async def list_videos(self, video_ids):  # noqa: ANN001
            self.listed.append(list(video_ids))
            raise RuntimeError("403 quotaExceeded")

    youtube = AlwaysBoom()
    totals = asyncio.run(_runner(db, youtube).run())

    # 200 channels would be 4 batches; it gave up after 3 consecutive failures.
    assert len(youtube.listed) == 3
    assert totals.quota_units == 3
    assert "update_channel_url" not in db.write_names()


# --- pass 2: fill the avatars ---------------------------------------------------


def test_pass2_resolves_and_stores_avatars() -> None:
    db = RoutingFakeDb()
    url_a = CHANNEL_URL.format(channel_id="UCalpha")
    url_b = CHANNEL_URL.format(channel_id="UCbravo")
    db.rows["avatar_targets"] = [
        {"channel_url": url_a, "known_avatar": ""},
        {"channel_url": url_b, "known_avatar": ""},
    ]
    youtube = FakeYouTube(
        channels={"UCalpha": _channel("UCalpha"), "UCbravo": _channel("UCbravo")}
    )

    totals = asyncio.run(_runner(db, youtube).run())

    assert youtube.channels_listed == [["UCalpha", "UCbravo"]]
    assert _params(db, "update_channel_avatar") == [
        {"channel_url": url_a, "channel_avatar_url": "https://yt3.ggpht.com/UCalpha"},
        {"channel_url": url_b, "channel_avatar_url": "https://yt3.ggpht.com/UCbravo"},
    ]
    assert totals.avatars_stored == 2
    assert totals.quota_units == 1  # 1 unit for the single channels.list call


def test_pass2_copies_a_sibling_row_avatar_without_spending_quota() -> None:
    """One row of a channel already knowing the avatar is enough — the avatar is a
    per-channel property, so no API call is needed to cover the channel's rest."""
    db = RoutingFakeDb()
    url = CHANNEL_URL.format(channel_id="UCalpha")
    db.rows["avatar_targets"] = [
        {"channel_url": url, "known_avatar": "https://yt3.ggpht.com/known"}
    ]
    youtube = FakeYouTube()

    totals = asyncio.run(_runner(db, youtube).run())

    assert youtube.channels_listed == []
    assert _params(db, "update_channel_avatar") == [
        {"channel_url": url, "channel_avatar_url": "https://yt3.ggpht.com/known"}
    ]
    assert totals.avatars_copied == 1
    assert totals.quota_units == 0


def test_pass2_counts_a_channel_the_api_returned_nothing_for() -> None:
    db = RoutingFakeDb()
    db.rows["avatar_targets"] = [
        {"channel_url": CHANNEL_URL.format(channel_id="UCghost"), "known_avatar": ""}
    ]

    totals = asyncio.run(_runner(db, FakeYouTube()).run())

    assert totals.avatars_stored == 0
    assert totals.avatars_unresolved == 1


# --- resume + limit -------------------------------------------------------------


def test_rerun_with_nothing_left_is_a_noop() -> None:
    """The resume contract: both passes derive targets from the CURRENT table
    state, so a completed backfill re-runs for free."""
    db = RoutingFakeDb()  # no handle_channels, no avatar_targets rows
    youtube = FakeYouTube()

    totals = asyncio.run(_runner(db, youtube).run())

    assert db.writes == []
    assert youtube.listed == [] and youtube.channels_listed == []
    assert totals.quota_units == 0


def test_limit_caps_channels_per_pass() -> None:
    db = RoutingFakeDb()
    db.rows["handle_channels"] = [
        {"channel_url": f"https://www.youtube.com/@c{i}", "video_ids": [f"v{i}"]}
        for i in range(5)
    ]
    db.rows["avatar_targets"] = [
        {"channel_url": CHANNEL_URL.format(channel_id=f"UC{i}"), "known_avatar": ""}
        for i in range(5)
    ]
    youtube = FakeYouTube(
        details={f"v{i}": _detail(f"v{i}", f"UCc{i}") for i in range(5)},
        channels={f"UC{i}": _channel(f"UC{i}") for i in range(5)},
    )

    asyncio.run(_runner(db, youtube, limit=2).run())

    assert youtube.listed == [["v0", "v1"]]
    assert youtube.channels_listed == [["UC0", "UC1"]]
