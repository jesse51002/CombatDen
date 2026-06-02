"""Absolute CDN URLs + S3 object keys for a run's image / icon assets.

In production the images/icons are served from S3 behind CloudFront
(`cdn.combatden.net`), not from this container. The object key mirrors the run
layout; the URL keeps the existing ``?v=<version>`` cache-buster the API already
emits (CloudFront is configured to include ``v`` in its cache key, so a new
content fingerprint is a fresh fetch with no invalidation).

Pure string helpers — no boto3, no config. Callers pass the CDN base
(`Settings.assets_cdn_base_url`); when that is empty (local dev) the API keeps
serving relative paths from the container instead.
"""

from __future__ import annotations

# Key prefix namespacing theme assets so the bucket can hold other classes later.
KEY_PREFIX = "themes"
IMAGE_SUFFIX = ".png"
ICON_SUFFIX = ".svg"


def image_key(app_id: str, run_id: str, slot_id: str) -> str:
    """S3 object key for an image slot's PNG (matches the served URL path)."""
    return f"{KEY_PREFIX}/{app_id}/{run_id}/images/{slot_id}{IMAGE_SUFFIX}"


def icon_key(app_id: str, run_id: str, slot_id: str) -> str:
    """S3 object key for an icon slot's SVG."""
    return f"{KEY_PREFIX}/{app_id}/{run_id}/icons/{slot_id}{ICON_SUFFIX}"


def cdn_url(base_url: str, key: str, version: str = "") -> str:
    """Absolute CDN URL for an object key, with the optional ``?v=`` cache-buster
    (CloudFront keys on ``v``, so a new version is a clean cache miss)."""
    url = f"{base_url.rstrip('/')}/{key}"
    return f"{url}?v={version}" if version else url
