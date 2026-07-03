"""Stage 1 — load the gym's latest spec and decide fresh vs incremental.

Reads the gym's criteria + queries from the append-only ``gym_video_spec_latest``
view, and derives ``criteria_changed``: did (videos_desc, avoid_desc) change since
the spec version that was latest as of the previous completed run? Because the
spec is append-only, that prior version is derivable (newest version created at or
before the prev run's timestamp) — no separate "last scanned spec" record needed.
A gym with no previous completed run is treated as changed (a fresh run).
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from pathlib import Path

from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql
from src.shared.util.jsonb import as_list

logger = logging.getLogger(__name__)

SQL_DIR = Path(__file__).resolve().parent / "sql"


@dataclass(frozen=True)
class SpecData:
    """The loaded spec plus the incremental-run context derived from it."""

    gym_id: str
    disciplines: list[str]
    videos_desc: str
    avoid_desc: str
    queries: list[str]
    # False → incremental (only new/changed videos rescanned, prior verdicts
    # carried forward). True → fresh (full rescan; only manual verdicts kept).
    criteria_changed: bool
    # The previous completed run's id, or None when the gym has never completed
    # a run. Anchors both the incremental exclude and the carry-forward.
    prev_run_id: str | None


class WorkerSpec:
    """Loads a gym's spec and computes its fresh/incremental run context."""

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db = db_pool

    async def load(self, gym_id: str) -> SpecData:
        """Load the gym's latest spec + fresh/incremental context.

        Raises ``ValueError`` when the gym has no spec authored yet (nothing to
        scan against).
        """
        row = await self._db.fetch_one(
            load_sql(SQL_DIR / "worker_spec_load_latest.sql"),
            {"gym_id": gym_id},
        )
        if row is None:
            raise ValueError(f"gym {gym_id} has no video spec")

        videos_desc = row["videos_desc"] or ""
        avoid_desc = row["avoid_desc"] or ""
        disciplines = [str(d) for d in as_list(row["gym_type"])]
        queries = [str(q) for q in as_list(row["queries"])]

        prev_run_id, criteria_changed = await self._incremental_context(
            gym_id, videos_desc, avoid_desc
        )
        logger.info(
            "spec for gym %s: %d queries, %d disciplines, "
            "criteria_changed=%s, prev_run=%s",
            gym_id,
            len(queries),
            len(disciplines),
            criteria_changed,
            prev_run_id,
        )
        return SpecData(
            gym_id=gym_id,
            disciplines=disciplines,
            videos_desc=videos_desc,
            avoid_desc=avoid_desc,
            queries=queries,
            criteria_changed=criteria_changed,
            prev_run_id=prev_run_id,
        )

    async def _incremental_context(
        self, gym_id: str, videos_desc: str, avoid_desc: str
    ) -> tuple[str | None, bool]:
        """(prev_run_id, criteria_changed) from the previous completed run.

        No previous completed run → (None, True): a fresh run. Otherwise compare
        the current criteria against whatever criteria that run scanned against.
        """
        prev = await self._db.fetch_one(
            load_sql(SQL_DIR / "worker_prev_completed_run.sql"),
            {"gym_id": gym_id},
        )
        if prev is None:
            return None, True
        prev_run_id = str(prev["run_id"])
        as_of = await self._db.fetch_one(
            load_sql(SQL_DIR / "worker_spec_as_of.sql"),
            {"gym_id": gym_id, "as_of": prev["created_at"]},
        )
        if as_of is None:
            return prev_run_id, True
        prior = (as_of["videos_desc"] or "", as_of["avoid_desc"] or "")
        changed = (videos_desc, avoid_desc) != prior
        return prev_run_id, changed
