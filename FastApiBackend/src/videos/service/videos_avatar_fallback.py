"""Serve-time channel-avatar fallback for the gym video feed.

The scraped pool carries no channel avatars — Apify never returned them — so
every pooled video's ``channel_avatar_url`` is empty. Rather than ship a blank
avatar circle on every card, the read path backfills an empty avatar with one of
the *gym's own* instructor headshots (the showcase class cards'
``instructor_image_url``).

This stays gym-agnostic: the headshots come from the gym's own class/employee
rows, never from Python. The pick is deterministic per video — the same video
always gets the same headshot — so avatars don't flicker between requests and
the client can cache them. A real avatar (when one exists) and a gym with no
class headshots are both left untouched.

This is a standalone, class-less concern module (free functions by design),
which the FastAPI service-layout rule allows.
"""

from __future__ import annotations

import zlib

from src.videos.schema.videos_schema import GymVideoCard, ShowcaseClassCard

# A YouTube watch URL's `?v=<id>` query value — the stable per-video key the
# deterministic headshot pick hashes. Falls back to the full URL when absent.
_VIDEO_ID_QUERY_KEY = "v="


def _video_id_from_url(url: str) -> str | None:
    """The YouTube video id embedded in a watch URL's ``?v=`` parameter, or None
    when the URL carries no such parameter."""
    marker = url.find(_VIDEO_ID_QUERY_KEY)
    if marker == -1:
        return None
    rest = url[marker + len(_VIDEO_ID_QUERY_KEY) :]
    # The id runs until the next query separator.
    for sep in ("&", "#"):
        cut = rest.find(sep)
        if cut != -1:
            rest = rest[:cut]
    return rest or None


def instructor_avatars(classes: list[ShowcaseClassCard]) -> list[str]:
    """The gym's instructor headshots, deduped and in first-seen order. Empty
    when no class has an instructor headshot (the caller then leaves avatars
    as-is)."""
    seen: dict[str, None] = {}
    for class_card in classes:
        if class_card.instructor_image_url:
            seen.setdefault(class_card.instructor_image_url, None)
    return list(seen)


def card_with_avatar(card: GymVideoCard, avatars: list[str]) -> GymVideoCard:
    """``card`` with an empty channel avatar backfilled from ``avatars``. A
    populated avatar, or an empty ``avatars`` pool, is returned unchanged. The
    headshot is chosen deterministically from a stable video key, so the same
    video always maps to the same face."""
    if card.channel_avatar_url.strip() or not avatars:
        return card
    key = _video_id_from_url(card.url) or card.url
    # crc32 is a stable, process-independent bucket (unlike salted `hash()`).
    picked = avatars[zlib.crc32(key.encode("utf-8")) % len(avatars)]
    return card.model_copy(update={"channel_avatar_url": picked})
