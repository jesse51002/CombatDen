"""BigGroup — the coarse two-way sort the frontend uses as its primary grouping:
**educational** vs **entertainment**, derived from a video's single
``VideoGenre`` tag.

Like the genre vocabulary itself, this is fixed shared vocabulary, not per-gym
config. The mapping: only ``educational`` and ``analysis`` are EDUCATIONAL;
every other genre is ENTERTAINMENT.
"""

from __future__ import annotations

import enum

from schema.video import VideoGenre


class BigGroup(enum.StrEnum):
    EDUCATIONAL = "educational"
    ENTERTAINMENT = "entertainment"


# The VideoGenre values that map to BigGroup.EDUCATIONAL.
# Every other genre is ENTERTAINMENT.
# Public so services can pass these as SQL parameters for the big-group filter.
EDUCATIONAL_GENRES: frozenset[VideoGenre] = frozenset(
    {VideoGenre.educational, VideoGenre.analysis}
)


def big_group_for(genre: VideoGenre) -> BigGroup:
    """The big group a single genre maps to."""
    if genre in EDUCATIONAL_GENRES:
        return BigGroup.EDUCATIONAL
    return BigGroup.ENTERTAINMENT
