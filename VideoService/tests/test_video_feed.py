"""The public feed projection: VideosFeed/VideoCard built straight from the
pooled VideoOutput objects, dropping the validation-only fields. The feed is
slim — just a page (total/limit/offset/videos), no tenant/company metadata."""

from __future__ import annotations

from schema import VideoCard, VideoOutput, VideosFeed


def _video() -> VideoOutput:
    return VideoOutput(
        url="https://www.youtube.com/watch?v=abc",
        title="A video",
        description="kept only for offline validation",
        thumbnail_url="https://i.ytimg.com/vi/abc/hqdefault.jpg",
        channel_name="Muay Thai Guy",
        channel_url="https://www.youtube.com/channel/c1",
        channel_avatar_url="https://yt3.ggpht.com/pfp",
        view_count=1000,
        like_count=50,
        tag="educational",  # maps to the educational big group
        source_queries=["how to teep"],
        relevance_index=3,
        transcript="the full caption text, stored but never served",
    )


def test_feed_projects_from_videos_and_drops_validation_fields() -> None:
    # The router builds VideosFeed straight from a list[VideoOutput]
    # (from_attributes coerces each to a VideoCard).
    videos = [_video()]
    feed = VideosFeed(total=len(videos), limit=20, offset=0, videos=videos)

    assert isinstance(feed.videos[0], VideoCard)
    card = feed.videos[0]
    assert card.url.endswith("abc")
    assert card.view_count == 1000
    assert card.tag is not None
    # big_group is the coarse sort, derived from the single tag.
    assert card.big_group.value == "educational"

    # The validation-only / internal fields are gone from the public payload.
    dumped_card = card.model_dump()
    for gone in (
        "description",
        "like_count",
        "source_queries",
        "transcript",
        "transcript_error",
        "gym_type",  # candidate-routing axis, internal — never served
    ):
        assert gone not in dumped_card
    assert "big_group" in dumped_card  # the derived field IS served
    assert dumped_card["relevance_index"] == 3  # relevance IS served

    # The pagination envelope is the whole feed — no company/app/tenant metadata.
    dumped_feed = feed.model_dump()
    assert dumped_feed["total"] == 1
    assert dumped_feed["limit"] == 20
    assert dumped_feed["offset"] == 0
    for gone in ("company_name", "app_id", "generated_at", "quota_units_estimate"):
        assert gone not in dumped_feed
