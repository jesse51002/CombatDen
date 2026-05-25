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

    EDUCATIONAL = "educational"  # teaching a techinque or concept.
    ANALYSIS = (
        "analysis"  # Post analysis of content, usually with the goal of educating.
    )
    ENTERTAINMENT = "entertainment"  # broad watch-for-fun content in the niche
    NEWS = "news"  # Current events, announcements, updates
    INTERVIEW = "interview"  # podcasts, Q&A, conversations with figures
    VLOG = "vlog"  # day-in-the-life, personal journeys
    PROFESSIONAL = "professional"  # pro/elite athletes & competitors performing, Specifically full matches or highlights from a specific event.
    CLIPS = "clips"  # A single video clip of a short moment or highlight or a video with multiple short moments or highlights
    Memes = "memes"  # Memes, lighthearted, funny moments
