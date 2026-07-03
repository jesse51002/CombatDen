"""Wire shape for one entry in an app's style list.

A "style" is a named run directory under ``apps/<app_id>/`` (e.g.
``ZenBJJ``) — distinct from the date-stamped pipeline runs, which a
picker never lists. Each summary carries just what a style picker
needs: the run id to load, the human design name to show, and a fetch
URL for the celebration image used as the card art.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict


class StyleSummary(BaseModel):
    """One selectable style for an app. ``id`` is the run id a client
    passes back to ``GET /apps/{app_id}/{id}``; ``display_name`` is the
    ``design_name`` from that run's ``output.yaml``; ``celebration_image``
    is a relative fetch URL (the client absolutises it, same convention
    as ``OutputResponse.images``); ``category`` is the app-declared
    classification bucket from the app.yaml ``style_categories`` map —
    required on the wire (an unclassified style is never listed)."""

    model_config = ConfigDict(extra="forbid")

    id: str
    display_name: str
    celebration_image: str
    category: str
