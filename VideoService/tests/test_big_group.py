"""BigGroup mapping: only educational/analysis are EDUCATIONAL; every other
genre is ENTERTAINMENT."""

from __future__ import annotations

import pytest

from schema import BigGroup, VideoType
from schema.big_group import big_group_for


@pytest.mark.parametrize(
    "video_type",
    [VideoType.EDUCATIONAL, VideoType.ANALYSIS],
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
        VideoType.PROFESSIONAL,
        VideoType.CLIPS,
        VideoType.Memes,
    ],
)
def test_entertainment_genres(video_type: VideoType) -> None:
    assert big_group_for(video_type) is BigGroup.ENTERTAINMENT
