"""Wire shape for a paginated style list.

Wraps the items in an envelope so clients can lazy-load page-by-page and
render "X of N" without a second roundtrip. ``total`` is the count after
the search filter — not the catalog size — so a paged UI can stop
fetching once it has rendered ``total`` items.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict

from src.api.schema.style_summary import StyleSummary


class StyleListResponse(BaseModel):
    """One page of an app's selectable styles.

    ``items`` is the slice; ``total`` is the post-filter match count
    (the full unsliced length); ``offset`` and ``limit`` echo the
    request so the client can compute ``hasMore = offset + len(items)
    < total`` without tracking what it asked for.
    """

    model_config = ConfigDict(extra="forbid")

    items: list[StyleSummary]
    total: int
    offset: int
    limit: int
