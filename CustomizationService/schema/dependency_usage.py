"""DependencyUsage — how one declared image dependency informs the image
it feeds.

When a slot declares ``depends_on`` images, the prompt-writing model
classifies each dependency as one of these while it writes the prompt.
``REFERENCE`` — the dependency only needs to steer style/continuity, so
its (text) prompt is folded into this image's prompt. ``DIRECT`` — the
output must contain that specific image (or something extremely close),
so the image itself is fed into the generator (image-conditioned
generation). The verdict is recorded on the output as provenance.
"""

from __future__ import annotations

import enum


class DependencyUsage(str, enum.Enum):
    """The two ways a dependency image can inform its dependent."""

    DIRECT = "direct"
    REFERENCE = "reference"
