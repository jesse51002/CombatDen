"""The YouTube video id of a watch URL.

The id is the natural key for a video: it names its per-video file under
``apps/<app_id>/videos/`` and ties an Apify transcript result back to the
video that asked for it. Shared by the store, the audit helpers, and the
transcripts pass so the parsing lives in exactly one place.
"""

from __future__ import annotations

from urllib.parse import parse_qs, urlparse


def video_id_from_url(url: str) -> str:
    """The YouTube video id from a watch URL (its ``v`` query param). Empty
    string when the URL carries no ``v`` (the caller decides what that means)."""
    return (parse_qs(urlparse(url).query).get("v") or [""])[0]
