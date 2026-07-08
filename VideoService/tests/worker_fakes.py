"""Shared fakes for the worker unit tests — no DB, no network.

``RoutingFakeDb`` stands in for ``DirectDatabasePool``: it routes each query to a
logical name by a distinctive token in the SQL, returns the rows the test
registered for that name (``[]`` / ``None`` by default), and records every read
and write so tests can assert on them. ``FakeLLM`` stands in for the LLM client
(``embed`` + ``complete_structured_with_cost``). ``FakeLock`` stands in for the
``ResourceLock``.
"""

from __future__ import annotations

from typing import Any, Callable


def route(sql: str) -> str:
    """The logical name for a worker SQL string, by a unique token in it."""
    checks = [
        ("count(*) AS runs_in_window", "system_count"),
        ("WITH spec_gyms AS", "select_due_gym"),
        ("'orphaned'", "fail_orphans"),
        ("error = :error", "fail_run"),
        ("SET status = 'completed'", "complete_run"),
        ("INSERT INTO video_run", "insert_run"),
        ("gym_video_spec_latest", "spec_latest"),
        ("SELECT run_id, created_at", "prev_run"),
        ("created_at <= :as_of", "spec_as_of"),
        ("jsonb_exists_any(source_queries", "tier1"),
        ("r.embedding <=>", "tier2"),
        ("SELECT video_id\nFROM gym_video_feed", "prev_verdicts"),
        ("video_run_id IS NULL", "owner_feed"),
        ("FROM video_rag\nWHERE video_id = ANY(:ids)", "existing_rag"),
        ("INSERT INTO video_rag", "insert_rag"),
        ("SET tag", "update_tags"),
        ("thumbnail_url", "load_videos_enrich"),
        ("JOIN video_rag r", "scan_candidates"),
        ("FROM video\nWHERE video_id = ANY(:ids)", "existing_videos"),
        ("INSERT INTO video (", "upsert_video"),
        ("INSERT INTO cost_log", "insert_cost"),
    ]
    for token, name in checks:
        if token in sql:
            return name
    if "INSERT INTO gym_video_feed" in sql:
        return "carry_forward" if "SELECT\n    gym_id" in sql else "insert_verdict"
    raise AssertionError(f"unrouted SQL:\n{sql[:200]}")


class _FakeResult:
    def __init__(self, rows: list[dict]) -> None:
        self._rows = rows

    def mappings(self) -> "_FakeResult":
        return self

    def all(self) -> list[dict]:
        return list(self._rows)


class _FakeSession:
    def __init__(self, db: "RoutingFakeDb") -> None:
        self._db = db

    async def __aenter__(self) -> "_FakeSession":
        return self

    async def __aexit__(self, *exc: object) -> None:
        return None

    async def execute(self, stmt: object, params: Any = None) -> _FakeResult:
        name = route(str(stmt))
        self._db.executes.append((name, str(stmt), params))
        return _FakeResult(self._db.session_rows.get(name, []))

    async def commit(self) -> None:
        self._db.commits += 1


class RoutingFakeDb:
    """A ``DirectDatabasePool`` stand-in that routes by SQL token."""

    def __init__(self) -> None:
        self.rows: dict[str, list[dict]] = {}
        self.ones: dict[str, dict | None] = {}
        self.session_rows: dict[str, list[dict]] = {}
        self.reads: list[tuple[str, str, Any]] = []
        self.writes: list[tuple[str, str, Any]] = []
        self.executes: list[tuple[str, str, Any]] = []
        self.commits = 0

    async def fetch_all(self, sql: str, params: Any = None) -> list[dict]:
        name = route(sql)
        self.reads.append(("fetch_all", name, params))
        return list(self.rows.get(name, []))

    async def fetch_one(self, sql: str, params: Any = None) -> dict | None:
        name = route(sql)
        self.reads.append(("fetch_one", name, params))
        return self.ones.get(name)

    async def execute_with_retry(
        self, sql: str, params: Any = None, max_retries: int = 3
    ) -> dict | None:
        name = route(sql)
        self.writes.append((name, sql, params))
        return self.ones.get(name)

    def session(self) -> _FakeSession:
        return _FakeSession(self)

    # --- test conveniences ---------------------------------------------------

    def write_names(self) -> list[str]:
        return [name for name, _, _ in self.writes]

    def execute_names(self) -> list[str]:
        return [name for name, _, _ in self.executes]

    def read_params(self, name: str) -> list[Any]:
        return [p for _, n, p in self.reads if n == name]


class FakeLLM:
    """LLM client stand-in: programmable ``embed`` + structured calls."""

    def __init__(
        self,
        structured: Callable[[dict], tuple[Any, float]] | None = None,
        *,
        embed_cost: float = 0.0,
        embed_dim: int = 3,
    ) -> None:
        self._structured = structured
        self.embed_cost = embed_cost
        self.embed_dim = embed_dim
        self.embed_calls: list[dict] = []
        self.structured_calls: list[dict] = []

    async def embed(
        self, texts: list[str], model: str
    ) -> tuple[list[list[float]], float]:
        self.embed_calls.append({"texts": list(texts), "model": model})
        vectors = [[0.1] * self.embed_dim for _ in texts]
        return vectors, self.embed_cost

    async def complete_structured_with_cost(
        self,
        messages: list[dict],
        *,
        schema: type,
        model: str,
        image_urls: list[str] | None = None,
    ) -> tuple[Any, float]:
        call = {
            "messages": messages,
            "schema": schema,
            "model": model,
            "image_urls": image_urls,
        }
        self.structured_calls.append(call)
        assert self._structured is not None, "no structured handler set"
        return self._structured(call)


class FakeLock:
    """ResourceLock stand-in recording acquire / renew / release."""

    def __init__(self, *, acquire: bool = True, renew: bool = True) -> None:
        self._acquire = acquire
        self._renew = renew
        self.acquired: list[tuple] = []
        self.renews = 0
        self.released: list[tuple] = []

    async def acquire_once(self, key, token, ttl_seconds=None) -> bool:  # noqa: ANN001
        self.acquired.append((key, token, ttl_seconds))
        return self._acquire

    async def renew(self, key, token, ttl_seconds=None) -> bool:  # noqa: ANN001
        self.renews += 1
        return self._renew

    async def release(self, key, token) -> None:  # noqa: ANN001
        self.released.append((key, token))
