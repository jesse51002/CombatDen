"""The public feed projection: VideosFeed/VideoCard built straight from the full
VideoOutput objects, dropping the validation-only fields."""

from __future__ import annotations

from datetime import datetime, timezone

from schema import VideoCard, VideoOutput, VideosFeed, VideosOutput


def _output() -> VideosOutput:
    return VideosOutput(
        company_name="Killer Muay Thai",
        app_id="combatden",
        generated_at=datetime.now(timezone.utc),
        quota_units_estimate=1402,
        videos=[
            VideoOutput(
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
            )
        ],
    )


def test_feed_projects_from_output_and_drops_validation_fields() -> None:
    # The router builds VideosFeed straight from a VideosOutput (from_attributes).
    feed = VideosFeed(
        company_name=_output().company_name,
        app_id=_output().app_id,
        generated_at=_output().generated_at,
        videos=_output().videos,  # list[VideoOutput] -> coerced to list[VideoCard]
    )
    assert isinstance(feed.videos[0], VideoCard)
    card = feed.videos[0]
    assert card.url.endswith("abc")
    assert card.view_count == 1000
    assert card.tag is not None

    # big_group is the coarse sort, derived from the single tag.
    assert card.big_group.value == "educational"

    # The validation-only / internal fields are gone from the public payload.
    dumped_card = card.model_dump()
    assert "description" not in dumped_card
    assert "like_count" not in dumped_card
    assert "source_queries" not in dumped_card
    assert "big_group" in dumped_card  # the new field IS served
    assert dumped_card["relevance_index"] == 3  # relevance IS served
    assert "quota_units_estimate" not in feed.model_dump()
