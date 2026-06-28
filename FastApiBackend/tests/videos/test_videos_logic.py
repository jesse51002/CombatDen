"""Pure-logic unit tests for the videos domain (no DB / no Stripe).

Covers the read-path transforms that don't need the database: the genre→group
and discipline→parent maps (asserted TOTAL so a new enum value can't silently go
unmapped), the serve-time channel-avatar backfill, the small null-safe helpers on
``VideosService``, and the owner-add YouTube-id extractor.
"""

import pytest
from schema.video import VideoGenre

from src.videos.schema.videos_big_group import BigGroup, big_group_for
from src.videos.schema.videos_gym_type import GymType
from src.videos.schema.videos_parent_gym_type import ParentGymType, parent_of
from src.videos.schema.videos_schema import GymVideoCard, ShowcaseClassCard
from src.videos.service.videos_avatar_fallback import (
    card_with_avatar,
    instructor_avatars,
)
from src.videos.service.videos_service import VideosService


def _card(avatar: str = "") -> GymVideoCard:
    return GymVideoCard(
        url="https://www.youtube.com/watch?v=abc123",
        title="t",
        thumbnail_url="thumb",
        channel_name="c",
        channel_url="cu",
        channel_avatar_url=avatar,
        relevance_index=0,
    )


def test_big_group_for_is_total_over_genres():
    # Every genre must map to a group (no KeyError / missing case).
    for genre in VideoGenre:
        assert isinstance(big_group_for(genre), BigGroup)


def test_big_group_educational_vs_entertainment():
    assert big_group_for(VideoGenre.educational) is BigGroup.EDUCATIONAL
    assert big_group_for(VideoGenre.analysis) is BigGroup.EDUCATIONAL
    assert big_group_for(VideoGenre.entertainment) is BigGroup.ENTERTAINMENT
    assert big_group_for(VideoGenre.memes) is BigGroup.ENTERTAINMENT


def test_parent_of_is_total_over_disciplines():
    # Exhaustive over GymType: a new discipline must declare its parent bucket.
    for discipline in GymType:
        assert isinstance(parent_of(discipline), ParentGymType)


def test_instructor_avatars_dedupes_and_skips_missing():
    classes = [
        ShowcaseClassCard(name="A", instructor_image_url="x"),
        ShowcaseClassCard(name="B", instructor_image_url=None),
        ShowcaseClassCard(name="C", instructor_image_url="x"),
        ShowcaseClassCard(name="D", instructor_image_url="y"),
    ]
    # First-seen order, deduped, None skipped.
    assert instructor_avatars(classes) == ["x", "y"]


def test_card_with_avatar_backfills_empty_only_and_is_deterministic():
    avatars = ["a", "b", "c"]
    filled = card_with_avatar(_card(""), avatars)
    assert filled.channel_avatar_url in avatars
    # Deterministic: the same video url always picks the same headshot.
    again = card_with_avatar(_card(""), avatars)
    assert again.channel_avatar_url == filled.channel_avatar_url
    # A populated avatar is left untouched.
    assert card_with_avatar(_card("real"), avatars).channel_avatar_url == "real"
    # An empty avatar pool is a no-op.
    assert card_with_avatar(_card(""), []).channel_avatar_url == ""


def test_instructor_name_null_safe():
    assert VideosService._instructor_name("Mary", "Jo") == "Mary Jo"
    assert VideosService._instructor_name("Mary", None) == "Mary"
    assert VideosService._instructor_name(None, "Jo") == "Jo"
    assert VideosService._instructor_name(None, None) is None


def test_as_list_tolerates_json_string_and_none():
    assert VideosService._as_list(None) == []
    assert VideosService._as_list('["a", "b"]') == ["a", "b"]
    assert VideosService._as_list(["a"]) == ["a"]


# ── owner-add: YouTube id extraction ─────────────────────────────────

_VALID_ID = "dQw4w9WgXcQ"  # 11 chars, the standard YouTube id shape


@pytest.mark.parametrize(
    "url",
    [
        f"https://www.youtube.com/watch?v={_VALID_ID}",
        f"https://www.youtube.com/watch?v={_VALID_ID}&t=42s",
        f"https://m.youtube.com/watch?v={_VALID_ID}",
        f"https://youtu.be/{_VALID_ID}",
        f"https://youtu.be/{_VALID_ID}?si=abcd",
        f"https://www.youtube.com/embed/{_VALID_ID}",
        f"https://www.youtube.com/shorts/{_VALID_ID}",
        f"https://www.youtube.com/live/{_VALID_ID}",
        f"youtube.com/watch?v={_VALID_ID}",  # scheme-less
        _VALID_ID,  # a bare id
    ],
)
def test_extract_youtube_id_accepts_known_forms(url: str):
    assert VideosService._extract_youtube_id(url) == _VALID_ID


@pytest.mark.parametrize(
    "url",
    [
        "",
        "   ",
        "https://vimeo.com/123456",
        "https://example.com/watch?v=" + _VALID_ID,  # right path, wrong host
        "https://www.youtube.com/watch?v=",  # no id
        "https://www.youtube.com/feed/subscriptions",  # no id segment
        "not a url at all",
        "https://youtu.be/short",  # too short to be an id
    ],
)
def test_extract_youtube_id_rejects_garbage(url: str):
    with pytest.raises(ValueError):
        VideosService._extract_youtube_id(url)
