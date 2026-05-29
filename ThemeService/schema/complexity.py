"""Complexity — the visual complexity tier of a generated image prompt.

A small model classifies the image-generation prompt into one of these
tiers right after it is written; the tier selects the image model's
``quality`` setting (a denser, busier prompt warrants more compute). It is
recorded on the output as provenance.
"""

from __future__ import annotations

import enum


class Complexity(str, enum.Enum):
    """The three prompt-complexity tiers."""

    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
