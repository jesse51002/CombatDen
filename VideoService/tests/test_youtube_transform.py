"""Pure transforms: raw YouTube response dicts -> VideoOutputs. No network.

Payloads carry bogus extra fields to prove tolerance to API drift. Searches no
longer carry tags, so videos leave the batch untagged; the dedup test proves
queries are merged across searches and the video stays untagged. Duration is
parsed from contentDetails."""

from __future__ import annotations

from scripts.youtube_batch.transform import (
    _parse_iso8601_duration,
    build_outputs,
    parse_channel_avatars,
    parse_search_response,
    parse_video_stats,
)


def _search_item(video_id: str, channel_id: str, *, title: str = "T") -> dict:
    return {
        "id": {"kind": "youtube#video", "videoId": video_id},
        "snippet": {
            "title": title,
            "description": "desc",
            "channelId": channel_id,
            "channelTitle": "Some Channel",
            "thumbnails": {
                "default": {"url": "low.jpg"},
                "high": {"url": "high.jpg"},
            },
            "unexpectedFutureField": "ignored",  # drift tolerance
        },
        "anotherBogusField": 123,
    }


def test_parse_search_picks_best_thumbnail_and_skips_non_videos() -> None:
    raw = {
        "items": [
            _search_item("v1", "c1"),
            {"id": {"kind": "youtube#channel", "channelId": "c9"}},  # not a video
        ],
        "etagBogus": "x",
    }
    hits = parse_search_response(raw, "teep tutorial")
    assert len(hits) == 1
    assert hits[0].video_id == "v1"
    assert hits[0].thumbnail_url == "high.jpg"  # high preferred over default
    assert hits[0].query == "teep tutorial"


def test_dedup_merges_queries_and_leaves_untagged() -> None:
    # Same video surfaces from two different searches.
    hits = parse_search_response(
        {"items": [_search_item("v1", "c1")]}, "q one"
    ) + parse_search_response({"items": [_search_item("v1", "c1")]}, "q two")
    outputs = build_outputs(hits, avatars={}, stats={})
    assert len(outputs) == 1  # de-duplicated
    assert outputs[0].tag is None  # untagged until the classification pass runs
    assert outputs[0].is_good is None
    assert set(outputs[0].source_queries) == {"q one", "q two"}


def test_relevance_index_is_position_and_best_across_queries() -> None:
    # In query A v_top is 1st (rank 0); in query B it's 2nd (rank 1).
    hits = parse_search_response(
        {"items": [_search_item("v_top", "c1"), _search_item("v_b", "c2")]}, "A"
    ) + parse_search_response(
        {"items": [_search_item("v_b", "c2"), _search_item("v_top", "c1")]}, "B"
    )
    by_url = {v.url: v for v in build_outputs(hits, avatars={}, stats={})}
    top = by_url["https://www.youtube.com/watch?v=v_top"]
    other = by_url["https://www.youtube.com/watch?v=v_b"]
    assert top.relevance_index == 0  # best rank across A(0) and B(1)
    assert other.relevance_index == 0  # best rank across A(1) and B(0)


def test_build_merges_avatars_and_stats_by_id() -> None:
    hits = parse_search_response({"items": [_search_item("v1", "c1")]}, "clips q")
    avatars = parse_channel_avatars(
        {"items": [{"id": "c1", "snippet": {"thumbnails": {"high": {"url": "pfp.jpg"}}}}]}
    )
    stats = parse_video_stats(
        {
            "items": [
                {
                    "id": "v1",
                    "statistics": {"viewCount": "999", "likeCount": "42"},
                    "contentDetails": {"duration": "PT5M30S"},
                }
            ]
        }
    )
    output = build_outputs(hits, avatars, stats)[0]
    assert output.url == "https://www.youtube.com/watch?v=v1"
    assert output.channel_url == "https://www.youtube.com/channel/c1"
    assert output.channel_avatar_url == "pfp.jpg"
    assert output.view_count == 999
    assert output.like_count == 42
    assert output.duration_seconds == 330  # 5m30s


def test_hidden_likes_and_missing_duration_parse_to_none() -> None:
    hits = parse_search_response({"items": [_search_item("v1", "c1")]}, "news q")
    stats = parse_video_stats(
        {"items": [{"id": "v1", "statistics": {"viewCount": "5"}}]}  # no likes/duration
    )
    output = build_outputs(hits, avatars={}, stats=stats)[0]
    assert output.view_count == 5
    assert output.like_count is None
    assert output.duration_seconds is None


def test_parse_iso8601_duration() -> None:
    assert _parse_iso8601_duration("PT5M30S") == 330
    assert _parse_iso8601_duration("PT1H") == 3600
    assert _parse_iso8601_duration("PT45S") == 45
    assert _parse_iso8601_duration("PT1H2M10S") == 3730
    assert _parse_iso8601_duration("P0D") is None  # live broadcast, no real runtime
    assert _parse_iso8601_duration("garbage") is None
    assert _parse_iso8601_duration(None) is None
