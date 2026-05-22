"""API error vocabulary."""

from __future__ import annotations


class NotFoundError(Exception):
    """A requested company brief does not exist (maps to HTTP 404)."""


class InvalidConfigError(Exception):
    """A `videos_config.yaml` exists on disk but is unparseable or no longer
    matches the current schema (maps to HTTP 422)."""
