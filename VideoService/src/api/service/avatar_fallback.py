"""Serve-time channel-avatar fallback for the video feed.

The scraped pool carries no channel avatars — Apify never returned them — so
every pooled video's ``channel_avatar_url`` is empty. Rather than ship a blank
avatar circle on every card, the read path backfills an empty avatar with one of
the *gym's own* instructor headshots (``Gym.classes[].instructor_image_url``).

This stays gym-agnostic: the headshots come from the gym's YAML, never from
Python. The pick is deterministic per video — the same video always gets the
same headshot — so avatars don't flicker between requests and the client can
cache them. A real avatar (when one exists) and a gym with no classes are both
left untouched.
"""

from __future__ import annotations

import zlib

from schema import Gym, VideoCard, VideoOutput
from src.shared.util.video_id import video_id_from_url


def instructor_avatars(gym: Gym) -> list[str]:
    """The gym's instructor headshots, deduped and in first-seen order. Empty
    when the gym has no classes authored (the caller then leaves avatars as-is)."""
    seen: dict[str, None] = {}
    for class_card in gym.classes or ():
        seen.setdefault(class_card.instructor_image_url, None)
    return list(seen)


def card_with_avatar(video: VideoOutput, avatars: list[str]) -> VideoCard:
    """The slim ``VideoCard`` for ``video``, with an empty channel avatar
    backfilled from ``avatars``. A populated avatar, or an empty ``avatars``
    pool, is returned unchanged. The headshot is chosen deterministically from a
    stable video key, so the same video always maps to the same face."""
    card = VideoCard.model_validate(video)
    if card.channel_avatar_url.strip() or not avatars:
        return card
    key = video_id_from_url(video.url) or video.url
    # crc32 is a stable, process-independent bucket (unlike salted ``hash()``).
    picked = avatars[zlib.crc32(key.encode("utf-8")) % len(avatars)]
    return card.model_copy(update={"channel_avatar_url": picked})
