"""BigGroup — the coarse two-way sort the frontend uses as its primary grouping:
**educational** vs **entertainment**, derived from a video's `VideoType` tags.

Like `VideoType`, this is fixed shared vocabulary, not per-company config. The
mapping: only `educational`, `tutorial`, and `informative` are EDUCATIONAL;
every other genre is ENTERTAINMENT. A video whose tags span both belongs to both.
"""

from __future__ import annotations

import enum
from collections.abc import Iterable

from schema.video_type import VideoType


class BigGroup(str, enum.Enum):
    EDUCATIONAL = "educational"
    ENTERTAINMENT = "entertainment"


# Only these map to EDUCATIONAL; every other VideoType is ENTERTAINMENT.
_EDUCATIONAL_TYPES: frozenset[VideoType] = frozenset(
    {VideoType.EDUCATIONAL, VideoType.TUTORIAL, VideoType.INFORMATIVE}
)


def big_group_for(video_type: VideoType) -> BigGroup:
    """The big group a single genre maps to."""
    if video_type in _EDUCATIONAL_TYPES:
        return BigGroup.EDUCATIONAL
    return BigGroup.ENTERTAINMENT


def big_groups_for_tags(tags: Iterable[VideoType]) -> list[BigGroup]:
    """The big groups a video belongs to, from its tags. Spanning both is
    allowed; order is stable (educational first)."""
    groups = {big_group_for(tag) for tag in tags}
    return [g for g in (BigGroup.EDUCATIONAL, BigGroup.ENTERTAINMENT) if g in groups]
