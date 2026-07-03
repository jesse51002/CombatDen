"""Tolerant JSONB decoding for raw SQL reads.

A JSONB column read back over SQLAlchemy + asyncpg can arrive either already
decoded (a Python ``list`` / ``dict``) or as the raw JSON string, depending on
the driver's type codecs. ``as_list`` normalises the array case so callers never
branch on it.
"""

from __future__ import annotations

import json


def as_list(value: object) -> list:
    """A JSONB array column as a Python list — tolerant of the driver returning
    either a decoded list or the raw JSON string. ``None`` → ``[]``."""
    if value is None:
        return []
    if isinstance(value, str):
        return json.loads(value)
    return list(value)  # already decoded by the driver
