"""WorkerScraper — no DB, no network.

Covers: the two-call YouTube fetch per query (search + list_videos) merge-upserts
into the pool; a failed query is dropped without aborting; the YouTube Data API is
free so search_usd is 0 and the run reports its (diagnostic) quota units.
"""

from __future__ import annotations

import asyncio

from src.worker.worker_scraper import QUOTA_UNITS_PER_SEARCH, WorkerScraper
from src.worker.worker_spec import SpecData
from tests.worker_fakes import FakeYouTube, RoutingFakeDb


def _search_item(vid: str) -> dict:
    return {
        "id": {"kind": "youtube#video", "videoId": vid},
        "snippet": {"title": f"Video {vid}", "channelId": "c1"},
    }


def _detail(vid: str) -> dict:
    return {
        "id": vid,
        "snippet": {"title": f"Video {vid}", "channelId": "c1"},
        "statistics": {"viewCount": "10", "likeCount": "1"},
        "contentDetails": {"duration": "PT2M"},
    }


def _spec(queries: list[str]) -> SpecData:
    return SpecData(
        gym_id="gym-1",
        disciplines=["mma"],
        videos_desc="v",
        avoid_desc="a",
        queries=queries,
        criteria_changed=False,
        prev_run_id=None,
    )


def test_scrape_merges_and_reports_free_search() -> None:
    db = RoutingFakeDb()
    db.rows["existing_videos"] = []  # both fresh → new
    youtube = FakeYouTube(
        search_items={"q one": [_search_item("a"), _search_item("b")]},
        details={"a": _detail("a"), "b": _detail("b")},
    )
    scraper = WorkerScraper(db, youtube)

    result = asyncio.run(scraper.scrape(_spec(["q one"])))

    assert youtube.searched == ["q one"]
    assert youtube.listed == [["a", "b"]]  # ids from the search feed videos.list
    assert result.results_fetched == 2
    assert result.new_count == 2 and result.updated_count == 0
    assert result.search_usd == 0.0  # YouTube Data API is free
    assert result.youtube_quota_units == QUOTA_UNITS_PER_SEARCH  # 1 query
    assert "upsert_video" in db.write_names()


def test_failed_query_is_dropped_not_fatal() -> None:
    db = RoutingFakeDb()
    db.rows["existing_videos"] = []

    class BoomThenOk(FakeYouTube):
        async def search(self, query, *, max_results, language):  # noqa: ANN001
            self.searched.append(query)
            if query == "boom":
                raise RuntimeError("quota exceeded")
            return [_search_item("ok")]

    youtube = BoomThenOk(details={"ok": _detail("ok")})
    scraper = WorkerScraper(db, youtube)

    result = asyncio.run(scraper.scrape(_spec(["boom", "good"])))

    # The good query still produced a video; the run did not abort.
    assert result.results_fetched == 1
    assert result.new_count == 1
    # Quota is charged per attempted spec query (a diagnostic).
    assert result.youtube_quota_units == 2 * QUOTA_UNITS_PER_SEARCH


def test_no_queries_is_a_noop() -> None:
    db = RoutingFakeDb()
    youtube = FakeYouTube()
    scraper = WorkerScraper(db, youtube)

    result = asyncio.run(scraper.scrape(_spec([])))

    assert result == type(result)(0.0, 0, 0, 0, 0)
    assert youtube.searched == []
    assert db.writes == []
