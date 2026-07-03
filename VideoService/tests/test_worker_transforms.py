"""Pure transforms for the worker's scrape stage: streamers/youtube-scraper
dataset items -> VideoOutput, incl. inline transcript, duration parsing, and
dedup across queries. No network. (Ported from the retired scraper transform.)"""

from __future__ import annotations

from src.worker.worker_transforms import build_outputs, parse_search_items


def _item(vid: str, **overrides: object) -> dict:
    item: dict = {
        "id": vid,
        "url": f"https://www.youtube.com/watch?v={vid}",
        "title": f"Video {vid}",
        "text": "a description",
        "thumbnailUrl": f"https://i.ytimg.com/vi/{vid}/hq.jpg",
        "channelName": "Some Channel",
        "channelUrl": "https://www.youtube.com/channel/c1",
        "channelAvatarUrl": "https://yt3.ggpht.com/avatar",
        "viewCount": 1000,
        "likes": 50,
        "duration": "5:30",
        "subtitles": [{"language": "en", "type": "auto", "srt": "hello world"}],
    }
    item.update(overrides)
    return item


def test_parse_and_build_basic() -> None:
    hits = parse_search_items([_item("abc")], "q one")
    out = build_outputs(hits)
    assert len(out) == 1
    v = out[0]
    assert v.url.endswith("v=abc")
    assert v.channel_avatar_url == "https://yt3.ggpht.com/avatar"
    assert v.view_count == 1000
    assert v.like_count == 50
    assert v.duration_seconds == 330  # 5:30 -> seconds
    assert v.transcript == "hello world"  # subtitle text inline
    assert v.source_queries == ["q one"]
    assert v.relevance_index == 0
    assert v.tag is None and v.gym_type == []  # untagged until enrich


def test_duration_int_and_hms() -> None:
    assert build_outputs(parse_search_items([_item("a", duration=95)], "q"))[
        0
    ].duration_seconds == 95
    assert build_outputs(parse_search_items([_item("b", duration="1:02:03")], "q"))[
        0
    ].duration_seconds == 3723


def test_hidden_counts_become_none() -> None:
    v = build_outputs(
        parse_search_items([_item("a", viewCount=None, likes=None)], "q")
    )[0]
    assert v.view_count is None
    assert v.like_count is None


def test_missing_subtitles_leaves_transcript_none() -> None:
    v = build_outputs(parse_search_items([_item("a", subtitles=[])], "q"))[0]
    assert v.transcript is None


def test_srt_shaped_payload_is_stripped() -> None:
    srt = (
        "1\n00:00:00,000 --> 00:00:02,000\nhello\n\n"
        "2\n00:00:02,000 --> 00:00:04,000\nworld"
    )
    v = build_outputs(
        parse_search_items([_item("a", subtitles=[{"srt": srt}])], "q")
    )[0]
    assert v.transcript == "hello world"  # cue numbers + timecodes stripped


def test_dedup_merges_queries_keeps_best_rank() -> None:
    hits = parse_search_items([_item("dup"), _item("x")], "q one")
    hits += parse_search_items([_item("y"), _item("dup")], "q two")  # dup rank 1
    out = build_outputs(hits)
    by_id = {v.url.split("v=")[1]: v for v in out}
    assert len(out) == 3  # dup de-duplicated
    assert set(by_id["dup"].source_queries) == {"q one", "q two"}
    assert by_id["dup"].relevance_index == 0  # best (lowest) rank kept


def test_non_video_items_skipped() -> None:
    out = build_outputs(
        parse_search_items([{"title": "no id or url"}, _item("ok")], "q")
    )
    assert [v.url.split("v=")[1] for v in out] == ["ok"]
