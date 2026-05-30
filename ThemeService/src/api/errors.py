"""API error vocabulary (kept apart from the pipeline's `core.errors`)."""

from __future__ import annotations


class NotFoundError(Exception):
    """A requested run or image does not exist (maps to HTTP 404)."""


class InvalidRunError(Exception):
    """A run exists on disk but its `output.yaml` is unparseable or no
    longer matches the current schema (maps to HTTP 422)."""
