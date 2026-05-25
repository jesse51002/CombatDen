"""BigGroup — the coarse two-way sort the frontend uses as its primary grouping:
**educational** vs **entertainment**, derived from a video's single `VideoType`.

Like `VideoType`, this is fixed shared vocabulary, not per-company config. The
mapping: only `educational` and `analysis` are EDUCATIONAL; every other genre is
ENTERTAINMENT.
"""

from __future__ import annotations

import enum

from schema.video_type import VideoType


class BigGroup(str, enum.Enum):
    EDUCATIONAL = "educational"
    ENTERTAINMENT = "entertainment"


# Only these map to EDUCATIONAL; every other VideoType is ENTERTAINMENT.
_EDUCATIONAL_TYPES: frozenset[VideoType] = frozenset(
    {VideoType.EDUCATIONAL, VideoType.ANALYSIS}
)


def big_group_for(video_type: VideoType) -> BigGroup:
    """The big group a single genre maps to."""
    if video_type in _EDUCATIONAL_TYPES:
        return BigGroup.EDUCATIONAL
    return BigGroup.ENTERTAINMENT
