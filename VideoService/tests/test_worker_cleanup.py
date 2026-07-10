"""WorkerCleanup — no DB (routed fake).

Covers: the strike-ceiling delete runs bound to ``worker_failure_max``, targets
videos at/above the ceiling, and returns the deleted count."""

from __future__ import annotations

import asyncio

from src.worker.worker_cleanup import WorkerCleanup
from src.worker.worker_config import settings
from tests.worker_fakes import RoutingFakeDb


def _executed(db: RoutingFakeDb, name: str):
    return [(s, p) for n, s, p in db.executes if n == name]


def test_cleanup_deletes_at_ceiling() -> None:
    db = RoutingFakeDb()
    # two videos are at/above the strike ceiling → deleted (FK cascades the rest).
    db.session_rows["cleanup_videos"] = [{"video_id": "x"}, {"video_id": "y"}]

    deleted = asyncio.run(WorkerCleanup(db).run())

    assert deleted == 2
    sql, params = _executed(db, "cleanup_videos")[0]
    assert "DELETE FROM video" in sql
    assert "failure_count >= :max_failures" in sql
    assert params == {"max_failures": settings.worker_failure_max}


def test_cleanup_none_to_delete() -> None:
    db = RoutingFakeDb()  # cleanup_videos → [] (nothing at the ceiling)

    deleted = asyncio.run(WorkerCleanup(db).run())

    assert deleted == 0
    assert db.execute_names() == ["cleanup_videos"]  # the delete still ran
