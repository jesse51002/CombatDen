"""WorkerScraper — no DB, no network.

Covers: the two-call YouTube fetch per query (search + list_videos) merge-upserts
into the pool; a failed query is dropped without aborting; the YouTube Data API is
free so search_usd is 0 and the run reports its (diagnostic) quota units; and the
scrape step's feed write — every funnel candidate is inserted as a 'pending' row
after the previous completed run's rows are carried forward (ALL rows incremental,
manual-only fresh, none on a first run).
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


def _feed_spec(*, criteria_changed: bool, prev_run_id: str | None) -> SpecData:
    return SpecData(
        gym_id="gym-1",
        disciplines=["mma"],
        videos_desc="v",
        avoid_desc="a",
        queries=["q"],
        criteria_changed=criteria_changed,
        prev_run_id=prev_run_id,
    )


def _sql_body(sql: str) -> str:
    """The SQL with -- comment lines stripped (the comment explains both modes)."""
    return "\n".join(
        line for line in sql.splitlines() if not line.strip().startswith("--")
    )


def _executed(db: RoutingFakeDb, name: str):
    return [(s, p) for n, s, p in db.executes if n == name]


def test_write_feed_incremental_carries_all_then_pending() -> None:
    db = RoutingFakeDb()
    scraper = WorkerScraper(db, FakeYouTube())

    asyncio.run(
        scraper.write_feed(
            _feed_spec(criteria_changed=False, prev_run_id="prev-1"),
            "run-1",
            ["a", "b"],
        )
    )

    # carry-forward runs BEFORE the pending insert (carried rows win the conflict).
    assert db.execute_names() == ["carry_forward", "insert_pending"]
    cf_sql = _sql_body(_executed(db, "carry_forward")[0][0])
    assert "curation_type = 'manual'" not in cf_sql  # incremental → all rows
    _, params = _executed(db, "insert_pending")[0]
    assert params == [
        {"gym_id": "gym-1", "video_id": "a", "run_id": "run-1"},
        {"gym_id": "gym-1", "video_id": "b", "run_id": "run-1"},
    ]


def test_write_feed_fresh_carries_only_manual() -> None:
    db = RoutingFakeDb()
    scraper = WorkerScraper(db, FakeYouTube())

    asyncio.run(
        scraper.write_feed(
            _feed_spec(criteria_changed=True, prev_run_id="prev-1"), "run-1", ["a"]
        )
    )

    cf_sql = _sql_body(_executed(db, "carry_forward")[0][0])
    assert "curation_type = 'manual'" in cf_sql  # fresh → only owner verdicts


def test_write_feed_first_run_skips_carry_forward() -> None:
    db = RoutingFakeDb()
    scraper = WorkerScraper(db, FakeYouTube())

    asyncio.run(
        scraper.write_feed(
            _feed_spec(criteria_changed=True, prev_run_id=None), "run-1", ["a"]
        )
    )

    assert db.execute_names() == ["insert_pending"]  # nothing to carry


def test_write_feed_no_candidates_still_carries() -> None:
    db = RoutingFakeDb()
    scraper = WorkerScraper(db, FakeYouTube())

    asyncio.run(
        scraper.write_feed(
            _feed_spec(criteria_changed=False, prev_run_id="prev-1"), "run-1", []
        )
    )

    # carry-forward still runs; no candidates → no pending insert.
    assert db.execute_names() == ["carry_forward"]
