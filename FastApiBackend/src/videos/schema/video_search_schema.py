"""Pydantic response models for semantic video search.

A result is a served feed card plus its cosine ``similarity`` to the embedded
query (1.0 = identical direction, 0.0 = orthogonal), ordered most-similar first.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field

import src.shared.db_schema_path  # noqa: F401
from src.videos.schema.videos_schema import GymVideoCard


class SearchResultCard(GymVideoCard):
    """A served feed card enriched with its cosine similarity to the query."""

    similarity: float


class VideoSearchResponse(BaseModel):
    """The semantic-search result list, most-similar first."""

    model_config = ConfigDict(extra="ignore")

    results: list[SearchResultCard] = Field(default_factory=list)
