"""Stage 3 — build the scan-candidate set (two tiers, budgeted, incremental).

Tier 1 (always in): pool videos this gym's own queries surfaced, discipline-
filtered (untagged fresh scrapes included so they reach enrich+scan). Tier 2 (RAG
probes): embed every spec query in ONE call, then for each query vector take the
nearest enriched videos (cosine) not already in tier 1. The union is capped at
``scan_budget_per_run`` — all of tier 1 first (truncated by relevance if it alone
exceeds the budget), then tier 2 by ascending distance. In incremental mode the
videos the previous completed run already verdicted are excluded (carried forward
instead of rescanned).
"""

from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass, field
from pathlib import Path

from src.shared.database import DirectDatabasePool
from src.shared.interfaces.llm_client import LLMClient
from src.shared.sql_loader import load_sql
from src.worker.worker_config import settings
from src.worker.worker_spec import SpecData

logger = logging.getLogger(__name__)

SQL_DIR = Path(__file__).resolve().parent / "sql"


@dataclass(frozen=True)
class FunnelResult:
    """The ordered candidate ids (tier 1 then tier 2) plus embed spend."""

    candidate_ids: list[str] = field(default_factory=list)
    tier1_count: int = 0
    tier2_count: int = 0
    embed_usd: float = 0.0


class WorkerFunnel:
    """Selects the videos a run will enrich + scan for one gym."""

    def __init__(self, db_pool: DirectDatabasePool, llm_client: LLMClient) -> None:
        self._db = db_pool
        self._llm = llm_client

    async def select(self, spec: SpecData) -> FunnelResult:
        """Compute this run's budgeted candidate set for ``spec``."""
        excluded = await self._incremental_excluded(spec)
        tier1 = await self._tier1(spec, excluded)

        budget = settings.scan_budget_per_run
        if len(tier1) >= budget:
            tier1 = tier1[:budget]
            logger.info(
                "gym %s funnel: %d tier-1 candidates (budget-capped, no probes)",
                spec.gym_id,
                len(tier1),
            )
            return FunnelResult(
                candidate_ids=tier1, tier1_count=len(tier1)
            )

        remaining = budget - len(tier1)
        tier2, embed_usd = await self._tier2(
            spec, exclude=set(tier1) | excluded, limit=remaining
        )
        candidates = tier1 + tier2
        logger.info(
            "gym %s funnel: %d tier-1 + %d tier-2 = %d candidates; embed $%.4f",
            spec.gym_id,
            len(tier1),
            len(tier2),
            len(candidates),
            embed_usd,
        )
        return FunnelResult(
            candidate_ids=candidates,
            tier1_count=len(tier1),
            tier2_count=len(tier2),
            embed_usd=embed_usd,
        )

    async def _incremental_excluded(self, spec: SpecData) -> set[str]:
        """The prev-run-verdicted ids to exclude in incremental mode (empty on a
        fresh run or a first run)."""
        if spec.criteria_changed or spec.prev_run_id is None:
            return set()
        rows = await self._db.fetch_all(
            load_sql(SQL_DIR / "worker_prev_run_verdicts.sql"),
            {"prev_run_id": spec.prev_run_id},
        )
        return {r["video_id"] for r in rows}

    async def _tier1(self, spec: SpecData, excluded: set[str]) -> list[str]:
        """Tier-1 candidate ids in relevance order, minus the incremental set."""
        rows = await self._db.fetch_all(
            load_sql(SQL_DIR / "worker_funnel_tier1.sql"),
            {"queries": spec.queries, "disciplines": spec.disciplines},
        )
        return [r["video_id"] for r in rows if r["video_id"] not in excluded]

    async def _tier2(
        self, spec: SpecData, *, exclude: set[str], limit: int
    ) -> tuple[list[str], float]:
        """RAG-probe candidate ids (best-distance union) + the embed cost."""
        if not spec.queries or limit <= 0:
            return [], 0.0
        vectors, embed_usd = await self._llm.embed(
            spec.queries, model=settings.embedding_model
        )
        exclude_ids = list(exclude)
        probes = await asyncio.gather(
            *(
                self._probe(vec, spec.disciplines, exclude_ids)
                for vec in vectors
            )
        )
        best: dict[str, float] = {}
        for rows in probes:
            for row in rows:
                vid = row["video_id"]
                dist = float(row["distance"])
                if vid not in best or dist < best[vid]:
                    best[vid] = dist
        ranked = sorted(best.items(), key=lambda kv: kv[1])
        taken = [vid for vid, _ in ranked if vid not in exclude][:limit]
        return taken, embed_usd

    async def _probe(
        self, vector: list[float], disciplines: list[str], exclude_ids: list[str]
    ) -> list[dict]:
        """One query vector's nearest enriched videos (discipline-filtered)."""
        return await self._db.fetch_all(
            load_sql(SQL_DIR / "worker_funnel_tier2.sql"),
            {
                "vec": self._vector_literal(vector),
                "disciplines": disciplines,
                "exclude_ids": exclude_ids,
                "top_k": settings.rag_probe_top_k,
            },
        )

    @staticmethod
    def _vector_literal(vector: list[float]) -> str:
        """A float list as the pgvector text form ``[f1,f2,...]`` (cast to
        ``vector`` in SQL)."""
        return "[" + ",".join(repr(float(f)) for f in vector) + "]"
