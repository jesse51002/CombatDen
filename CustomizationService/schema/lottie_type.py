"""LottieType — the kind of animation a Lottie preset can serve as.

A curated preset carries one or more of these as tags (a preset can be
both). A lottie *slot* declares exactly one ``required_type``; only
presets carrying that tag are offered to the selection LLM.

- ``STANDALONE`` — plays on its own, no dependency on anything else.
- ``REVEAL`` — plays in the background while an image is revealed (e.g.
  an electric field before a streak icon appears). A reveal-capable
  preset declares a single fixed insertion point where the revealed
  image composites.
"""

from __future__ import annotations

import enum


class LottieType(str, enum.Enum):
    """The two animation roles a preset can fill."""

    STANDALONE = "standalone"
    REVEAL = "reveal"
