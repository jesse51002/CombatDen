"""Serve-time channel-avatar backfill: an empty ``channel_avatar_url`` is filled
from the gym's instructor headshots, deterministically per video; a real avatar
and a gym with no classes are both left untouched."""

from __future__ import annotations

from schema import ClassImage, Gym, GymSpecifications, GymVideos, VideoOutput
from schema.gym_type import GymType
from src.api.service.avatar_fallback import card_with_avatar, instructor_avatars

AVATARS = ["https://img/c0.jpg", "https://img/c1.jpg", "https://img/c2.jpg"]


def _video(vid: str = "abc123", *, avatar: str = "") -> VideoOutput:
    return VideoOutput(
        url=f"https://www.youtube.com/watch?v={vid}",
        title="t",
        description="d",
        thumbnail_url="th",
        channel_name="Chan",
        channel_url="cu",
        channel_avatar_url=avatar,
        source_queries=["q"],
        relevance_index=0,
        tag=None,
    )


def _class(i: int, image: str) -> ClassImage:
    return ClassImage(
        name=f"Class {i}",
        image_url=f"https://img/{i}.jpg",
        description="about the class",
        instructor_name=f"Coach {i}",
        instructor_bio="bio",
        instructor_image_url=image,
    )


def _gym(classes: list[ClassImage] | None) -> Gym:
    return Gym(
        gym_id="vinyasa",
        gym_type=[GymType.VINYASA],
        theme="VinyasaFlow",
        videos=GymVideos(
            specification=GymSpecifications(videos_desc="vids", avoid_desc="none"),
            good_video_ids=[],
            rejected_video_ids=[],
        ),
        classes=classes,
    )


# --- instructor_avatars ------------------------------------------------------


def test_instructor_avatars_collects_headshots_in_order() -> None:
    gym = _gym([_class(0, "h0"), _class(1, "h1"), _class(2, "h2")])
    assert instructor_avatars(gym) == ["h0", "h1", "h2"]


def test_instructor_avatars_dedupes_shared_roster() -> None:
    # the shared roster repeats the same headshot across multiple classes
    gym = _gym([_class(0, "h0"), _class(1, "h0"), _class(2, "h1")])
    assert instructor_avatars(gym) == ["h0", "h1"]


def test_instructor_avatars_empty_when_no_classes() -> None:
    assert instructor_avatars(_gym(None)) == []


# --- card_with_avatar --------------------------------------------------------


def test_empty_avatar_is_backfilled_from_pool() -> None:
    card = card_with_avatar(_video(avatar=""), AVATARS)
    assert card.channel_avatar_url in AVATARS


def test_real_avatar_is_preserved() -> None:
    card = card_with_avatar(_video(avatar="https://real/avatar.jpg"), AVATARS)
    assert card.channel_avatar_url == "https://real/avatar.jpg"


def test_whitespace_only_avatar_treated_as_empty() -> None:
    card = card_with_avatar(_video(avatar="   "), AVATARS)
    assert card.channel_avatar_url in AVATARS


def test_empty_pool_leaves_avatar_empty() -> None:
    card = card_with_avatar(_video(avatar=""), [])
    assert card.channel_avatar_url == ""


def test_pick_is_deterministic_per_video() -> None:
    first = card_with_avatar(_video("vidA", avatar=""), AVATARS).channel_avatar_url
    again = card_with_avatar(_video("vidA", avatar=""), AVATARS).channel_avatar_url
    assert first == again  # same video -> same headshot across calls


def test_pick_spreads_across_the_pool() -> None:
    picks = {
        card_with_avatar(_video(f"vid{i}", avatar=""), AVATARS).channel_avatar_url
        for i in range(20)
    }
    assert len(picks) > 1  # not one fixed face for every video


def test_card_preserves_other_fields() -> None:
    card = card_with_avatar(_video("xyz", avatar=""), AVATARS)
    assert card.url == "https://www.youtube.com/watch?v=xyz"
    assert card.channel_name == "Chan"
