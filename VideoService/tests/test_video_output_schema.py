"""VideosOutput / VideoOutput round-trip, plus the deliberate extra="ignore"
tolerance (these documents are machine-written from YouTube responses, so they
must survive unknown fields rather than fail loudly)."""

from __future__ import annotations

from datetime import datetime, timezone

from schema import VideoOutput, VideosOutput


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


def _output() -> dict:
    return {
        "company_name": "Killer Muay Thai",
        "app_id": "combatden",
        "generated_at": datetime.now(timezone.utc),
        "quota_units_estimate": 1402,
        "videos": [_video()],
    }


def test_video_output_round_trips() -> None:
    video = VideoOutput.model_validate(_video())
    assert video.tag is not None
    assert video.view_count == 412903


def test_videos_output_round_trips() -> None:
    output = VideosOutput.model_validate(_output())
    assert output.app_id == "combatden"
    assert len(output.videos) == 1


def test_manifest_queries_default_and_round_trip() -> None:
    doc = _output()
    del doc["videos"]
    assert VideosOutput.model_validate(doc).queries == []  # default empty
    doc["queries"] = ["bjj fundamentals", "white belt vlog"]
    assert VideosOutput.model_validate(doc).queries == ["bjj fundamentals", "white belt vlog"]


def test_hidden_counts_are_none() -> None:
    doc = _video()
    del doc["view_count"]
    del doc["like_count"]
    video = VideoOutput.model_validate(doc)
    assert video.view_count is None
    assert video.like_count is None


def test_extra_keys_are_ignored_not_rejected() -> None:
    """The whole point of extra="ignore": unknown YouTube fields are dropped."""
    doc = _video()
    doc["dislike_count"] = 7  # field YouTube no longer returns
    doc["some_future_field"] = {"nested": True}
    video = VideoOutput.model_validate(doc)
    assert not hasattr(video, "dislike_count")


def test_untagged_allowed_before_classification() -> None:
    # The batch writes videos untagged; the classification pass fills the tag.
    doc = _video()
    del doc["tag"]
    video = VideoOutput.model_validate(doc)
    assert video.tag is None
    assert video.is_good is None  # not yet classified


def test_classification_fields_round_trip() -> None:
    doc = _video()
    doc["tag"] = "clips"
    doc["is_good"] = False
    doc["duration_seconds"] = 95
    video = VideoOutput.model_validate(doc)
    assert video.tag.value == "clips"
    assert video.is_good is False
    assert video.duration_seconds == 95


def test_videos_default_to_empty_list() -> None:
    doc = _output()
    del doc["videos"]
    assert VideosOutput.model_validate(doc).videos == []


def test_transcript_defaults_none_and_is_last_field() -> None:
    # Untouched by the batch / classify; filled by the transcripts pass.
    assert VideoOutput.model_validate(_video()).transcript is None
    # Declared last so it lands at the bottom of each per-video file.
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


def test_reason_defaults_none_and_round_trips() -> None:
    assert VideoOutput.model_validate(_video()).reason is None
    doc = _video()
    doc["is_good"] = False
    doc["reason"] = "no_transcript"
    video = VideoOutput.model_validate(doc)
    assert video.reason.value == "no_transcript"
