"""Human-readable runtime formatting.

``format_duration`` renders a video's runtime in seconds as a compact string
(``5m30s`` / ``1h2m`` / ``45s``), or ``unknown`` when the source reported no
duration (e.g. a live broadcast). Shared by the internal viewer and the worker's
enrich prompt so the formatting lives in exactly one place.
"""

from __future__ import annotations


def format_duration(seconds: int | None) -> str:
    """Human runtime: ``5m30s`` / ``1h2m`` / ``45s``. ``unknown`` when the
    source reported no duration."""
    if seconds is None:
        return "unknown"
    hours, rem = divmod(seconds, 3600)
    minutes, secs = divmod(rem, 60)
    parts = []
    if hours:
        parts.append(f"{hours}h")
    if minutes:
        parts.append(f"{minutes}m")
    if secs or not parts:
        parts.append(f"{secs}s")
    return "".join(parts)
