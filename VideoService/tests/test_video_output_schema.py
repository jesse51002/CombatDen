"""VideoOutput round-trip — the per-video pool record. ``extra="ignore"`` is
deliberate: these documents are machine-written from the Apify scraper, so they
must survive (and drop) unknown fields rather than fail loudly. There is no
manifest wrapper — the pool is just a folder of these."""

from __future__ import annotations

from schema import VideoOutput


def _video() -> dict:
    return {
        "url": "https://www.youtube.com/watch?v=abc123",
        "title": "How to Throw a Teep Kick",
        "description": "A step-by-step breakdown.",
        "thumbnail_url": "https://i.ytimg.com/vi/abc123/hqdefault.jpg",
        "channel_name": "Muay Thai Guy",
        "channel_url": "https://www.youtube.com/channel/UC123",
        "channel_avatar_url": "https://yt3.ggpht.com/avatar",
        "view_count": 412903,
        "like_count": 11820,
        "tag": "educational",
        "source_queries": ["how to throw a teep kick step by step"],
        "relevance_index": 0,
    }


def test_video_output_round_trips() -> None:
    video = VideoOutput.model_validate(_video())
    assert video.tag is not None
    assert video.view_count == 412903


def test_hidden_counts_are_none() -> None:
    doc = _video()
    del doc["view_count"]
    del doc["like_count"]
    video = VideoOutput.model_validate(doc)
    assert video.view_count is None
    assert video.like_count is None


def test_extra_keys_are_ignored_not_rejected() -> None:
    """The whole point of extra="ignore": unknown scraper fields are dropped."""
    doc = _video()
    doc["dislike_count"] = 7  # field YouTube no longer returns
    doc["some_future_field"] = {"nested": True}
    video = VideoOutput.model_validate(doc)
    assert not hasattr(video, "dislike_count")


def test_untagged_allowed_before_classification() -> None:
    # The scrape writes videos untagged; the classify pass fills tag + gym_type.
    doc = _video()
    del doc["tag"]
    video = VideoOutput.model_validate(doc)
    assert video.tag is None
    assert video.gym_type == []  # not yet tagged


def test_pool_tag_fields_round_trip() -> None:
    doc = _video()
    doc["tag"] = "clips"
    doc["gym_type"] = ["muay_thai", "kickboxing"]
    doc["duration_seconds"] = 95
    video = VideoOutput.model_validate(doc)
    assert video.tag.value == "clips"
    assert [g.value for g in video.gym_type] == ["muay_thai", "kickboxing"]
    assert video.duration_seconds == 95


def test_transcript_defaults_none_and_is_last_field() -> None:
    # Filled inline by the scrape; declared last so it lands at the bottom of
    # each per-video file.
    assert VideoOutput.model_validate(_video()).transcript is None
    assert list(VideoOutput.model_fields)[-1] == "transcript"


def test_transcript_round_trips() -> None:
    doc = _video()
    doc["transcript"] = "welcome back to the channel, today we work the teep..."
    video = VideoOutput.model_validate(doc)
    assert video.transcript.startswith("welcome back")


def test_transcript_error_defaults_none_and_round_trips() -> None:
    assert VideoOutput.model_validate(_video()).transcript_error is None
    doc = _video()
    doc["transcript_error"] = "AgeRestricted"
    assert VideoOutput.model_validate(doc).transcript_error == "AgeRestricted"


def test_gym_type_defaults_empty_and_round_trips() -> None:
    # Untagged until the classify pass runs; then a list of disciplines.
    assert VideoOutput.model_validate(_video()).gym_type == []
    doc = _video()
    doc["gym_type"] = ["rowing"]
    assert VideoOutput.model_validate(doc).gym_type[0].value == "rowing"


def test_is_good_is_not_a_pool_field() -> None:
    # Approval is per-gym (held on the gym's good/rejected lists), never on the
    # pool video; a stray is_good is ignored.
    doc = _video()
    doc["is_good"] = True
    video = VideoOutput.model_validate(doc)
    assert not hasattr(video, "is_good")


def test_source_queries_required() -> None:
    # A pooled video must record at least one query that surfaced it.
    doc = _video()
    del doc["source_queries"]
    import pytest

    with pytest.raises(Exception):
        VideoOutput.model_validate(doc)
