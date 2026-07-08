"""Pure transforms for the worker's scrape stage: YouTube Data API items
(search.list merged with videos.list) -> VideoOutput, incl. ISO-8601 duration
parsing and dedup across queries. No network. Transcripts are NOT here — they are
fetched lazily at enrich, so a scraped VideoOutput leaves with transcript=None."""

from __future__ import annotations

from src.worker.worker_transforms import (
    build_outputs,
    parse_youtube_items,
    youtube_item_id,
)


def _search_item(vid: str, **snippet_overrides: object) -> dict:
    snippet: dict = {
        "title": f"Video {vid}",
        "description": "a short (truncated) description",
        "channelTitle": "Some Channel",
        "channelId": "c1",
        "thumbnails": {
            "default": {"url": f"https://i.ytimg.com/vi/{vid}/default.jpg"},
            "high": {"url": f"https://i.ytimg.com/vi/{vid}/hq.jpg"},
        },
    }
    snippet.update(snippet_overrides)
    return {"id": {"kind": "youtube#video", "videoId": vid}, "snippet": snippet}


def _detail(vid: str, *, duration: str = "PT5M30S", **overrides: object) -> dict:
    detail: dict = {
        "id": vid,
        "snippet": {
            "title": f"Video {vid}",
            "description": "the full un-truncated description",
            "channelTitle": "Some Channel",
            "channelId": "c1",
            "thumbnails": {
                "high": {"url": f"https://i.ytimg.com/vi/{vid}/hq.jpg"},
                "maxres": {"url": f"https://i.ytimg.com/vi/{vid}/maxres.jpg"},
            },
        },
        "statistics": {"viewCount": "1000", "likeCount": "50"},
        "contentDetails": {"duration": duration},
    }
    detail.update(overrides)
    return detail


def _parse(vids: list[str], query: str, **detail_kwargs: object):
    search = [_search_item(v) for v in vids]
    details = {v: _detail(v, **detail_kwargs) for v in vids}
    return parse_youtube_items(search, details, query)


def test_parse_and_build_basic() -> None:
    out = build_outputs(_parse(["abc"], "q one"))
    assert len(out) == 1
    v = out[0]
    assert v.url.endswith("v=abc")
    assert v.channel_url == "https://www.youtube.com/channel/c1"
    assert v.channel_avatar_url == ""  # the API snippet has no avatar
    assert v.thumbnail_url.endswith("/maxres.jpg")  # highest-res picked
    assert v.description == "the full un-truncated description"  # detail wins
    assert v.view_count == 1000
    assert v.like_count == 50
    assert v.duration_seconds == 330  # PT5M30S -> seconds
    assert v.transcript is None  # fetched later, at enrich
    assert v.source_queries == ["q one"]
    assert v.relevance_index == 0
    assert v.tag is None and v.gym_type == []  # untagged until enrich


def test_iso8601_duration_variants() -> None:
    assert build_outputs(_parse(["a"], "q", duration="PT45S"))[0].duration_seconds == 45
    assert (
        build_outputs(_parse(["b"], "q", duration="PT1H2M3S"))[0].duration_seconds
        == 3723
    )
    assert build_outputs(_parse(["c"], "q", duration="PT1M"))[0].duration_seconds == 60
    # A live broadcast / zero-length reports P0D / PT0S -> None.
    assert build_outputs(_parse(["d"], "q", duration="P0D"))[0].duration_seconds is None


def test_hidden_counts_become_none() -> None:
    # likeCount is omitted when hidden; a missing/blank viewCount -> None too.
    search = [_search_item("a")]
    details = {"a": _detail("a", statistics={})}
    v = build_outputs(parse_youtube_items(search, details, "q"))[0]
    assert v.view_count is None
    assert v.like_count is None


def test_missing_details_falls_back_to_search_snippet() -> None:
    # No videos.list detail for this id: title/description come from search, and
    # duration/stats are simply absent.
    v = build_outputs(parse_youtube_items([_search_item("a")], {}, "q"))[0]
    assert v.title == "Video a"
    assert v.description == "a short (truncated) description"
    assert v.duration_seconds is None
    assert v.view_count is None


def test_dedup_merges_queries_keeps_best_rank() -> None:
    hits = _parse(["dup", "x"], "q one")
    hits += _parse(["y", "dup"], "q two")  # dup is rank 1 in this query
    out = build_outputs(hits)
    by_id = {v.url.split("v=")[1]: v for v in out}
    assert len(out) == 3  # dup de-duplicated
    assert set(by_id["dup"].source_queries) == {"q one", "q two"}
    assert by_id["dup"].relevance_index == 0  # best (lowest) rank kept


def test_non_video_items_skipped() -> None:
    out = build_outputs(
        parse_youtube_items(
            [{"id": {"kind": "youtube#channel"}}, _search_item("ok")], {}, "q"
        )
    )
    assert [v.url.split("v=")[1] for v in out] == ["ok"]


def test_youtube_item_id_handles_both_shapes() -> None:
    assert youtube_item_id({"id": {"videoId": "abc"}}) == "abc"  # search.list
    assert youtube_item_id({"id": "xyz"}) == "xyz"  # videos.list
    assert youtube_item_id({"id": {"kind": "youtube#channel"}}) == ""
    assert youtube_item_id({}) == ""
