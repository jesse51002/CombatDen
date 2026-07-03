"""VideoSearchService — semantic search over a gym's served video feed.

Embeds a free-text query once, then ranks the gym's served + enriched feed by
cosine similarity to each video's summary embedding. No bucket filter — this is
staff-facing full-feed search, not the member rec surface.
"""

from __future__ import annotations

from uuid import UUID

from sqlalchemy import text

from src.shared.database import DirectDatabasePool
from src.shared.litellm_client import LiteLLMClient
from src.shared.sql_loader import load_sql
from src.videos import SQL_DIR
from src.videos.schema.video_search_schema import SearchResultCard


class VideoSearchService:
    """Embed a query and rank a gym's served feed by summary similarity."""

    def __init__(
        self,
        *,
        db_pool: DirectDatabasePool,
        litellm_client: LiteLLMClient,
        embedding_model: str,
        embedding_dim: int,
    ) -> None:
        self._db = db_pool
        self._litellm = litellm_client
        self._embedding_model = embedding_model
        self._embedding_dim = embedding_dim

    async def search(
        self, gym_id: UUID, q: str, limit: int
    ) -> list[SearchResultCard]:
        """Return the ``limit`` most-similar served videos for the query ``q``."""
        embeddings = await self._litellm.embed(
            texts=[q], model=self._embedding_model
        )
        query_embedding = embeddings[0]
        if len(query_embedding) != self._embedding_dim:
            raise ValueError(
                f"embedding dimension {len(query_embedding)} != expected "
                f"{self._embedding_dim} (model {self._embedding_model})"
            )

        sql = load_sql(SQL_DIR / "video_search_candidates.sql")
        params = {
            "gym_id": str(gym_id),
            "query_embedding": self._to_vector_literal(query_embedding),
            "limit": limit,
        }
        async with self._db.session() as session:
            rows = (
                (await session.execute(text(sql), params)).mappings().all()
            )

        results: list[SearchResultCard] = []
        for row in rows:
            try:
                results.append(SearchResultCard.model_validate(dict(row)))
            except ValueError:
                continue
        return results

    @staticmethod
    def _to_vector_literal(vec: list[float]) -> str:
        """Serialize a vector to pgvector text form ``'[0.1,0.2,...]'``."""
        return "[" + ",".join(str(x) for x in vec) + "]"
