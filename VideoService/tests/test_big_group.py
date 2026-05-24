"""BigGroup mapping: only educational/tutorial/informative are EDUCATIONAL;
every other genre is ENTERTAINMENT. A video's tags can span both."""

from __future__ import annotations

import pytest

from schema import BigGroup, VideoType
from schema.big_group import big_group_for, big_groups_for_tags


@pytest.mark.parametrize(
    "video_type",
    [VideoType.EDUCATIONAL, VideoType.TUTORIAL, VideoType.INFORMATIVE],
)
def test_educational_genres(video_type: VideoType) -> None:
    assert big_group_for(video_type) is BigGroup.EDUCATIONAL


@pytest.mark.parametrize(
    "video_type",
    [
        VideoType.ENTERTAINMENT,
        VideoType.NEWS,
        VideoType.INTERVIEW,
        VideoType.VLOG,
        VideoType.BEHIND_THE_SCENES,
        VideoType.PROFESSIONAL,
        VideoType.CLIPS,
        VideoType.FUN,
    ],
)
def test_entertainment_genres(video_type: VideoType) -> None:
    assert big_group_for(video_type) is BigGroup.ENTERTAINMENT


def test_spanning_tags_yield_both_educational_first() -> None:
    groups = big_groups_for_tags([VideoType.CLIPS, VideoType.TUTORIAL])
    assert groups == [BigGroup.EDUCATIONAL, BigGroup.ENTERTAINMENT]


def test_single_group_when_tags_dont_span() -> None:
    assert big_groups_for_tags([VideoType.FUN, VideoType.CLIPS]) == [
        BigGroup.ENTERTAINMENT
    ]
