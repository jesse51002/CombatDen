"""VideoType — the content-genre tag on each search prompt.

The fixed, shared vocabulary every `videos_config.yaml` draws from. A brief's
searches must span this spectrum — from watch-for-fun entertainment through
teaching content, news, personal vlogs, to top-level professional performance
and short clips. Serializes as its lowercase value in YAML.
"""

from __future__ import annotations

import enum


class VideoType(str, enum.Enum):
    """A YouTube content genre. Searches carry one or more of these."""

    ENTERTAINMENT = "entertainment"          # broad watch-for-fun content in the niche
    EDUCATIONAL = "educational"              # teaching concepts, explainers, courses
    TUTORIAL = "tutorial"                    # step-by-step how-to / technique
    INFORMATIVE = "informative"              # facts, breakdowns, analysis, deep dives
    NEWS = "news"                            # current events, announcements, updates
    INTERVIEW = "interview"                  # podcasts, Q&A, conversations with figures
    VLOG = "vlog"                            # day-in-the-life, personal journeys
    BEHIND_THE_SCENES = "behind_the_scenes"  # process, making-of, business/gym operations
    PROFESSIONAL = "professional"            # PROS practising the craft at the top level —
                                             # pro/elite athletes & competitors performing,
                                             # pro competition footage (NOT corporate video)
    CLIPS = "clips"                          # short highlights, moments, compilations
    FUN = "fun"                              # memes, lighthearted, funny moments
