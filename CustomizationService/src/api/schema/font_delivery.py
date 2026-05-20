"""Wire shape for the font delivery endpoint.

Returned by ``GET /apps/{app_id}/{run_id}/fonts/{slot_id}``. Carries
the canonical Google Fonts family plus the per-variant font-file URLs
the frontend can fetch directly from ``fonts.gstatic.com``. The Google
Fonts Developer API hands back TTF URLs (which every consumer — web,
Flutter, native — can load), so ``variants`` maps each variant label
(``"regular"``, ``"700"``, etc.) to a ``.ttf`` URL. ``css_url`` is the
standard Google Fonts CSS2 endpoint: a convenience for web clients,
which Google serves with the woff2 variant under a browser user-agent.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict


class FontDeliveryResponse(BaseModel):
    """One font slot's deliverable: family, category, fetch URLs."""

    model_config = ConfigDict(extra="forbid")

    family: str
    category: str
    css_url: str
    variants: dict[str, str]
