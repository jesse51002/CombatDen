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
        ("DELETE FROM video", "cleanup_videos"),
        (":complete_fraction", "finalize_complete"),
        ("'no feed rows'", "finalize_fail"),
        ("error = :error", "fail_run"),
        ("INSERT INTO video_run", "insert_run"),
        ("gym_video_spec_latest", "spec_latest"),
        ("SELECT run_id, created_at", "prev_run"),
        ("created_at <= :as_of", "spec_as_of"),
        ("jsonb_exists_any(source_queries", "tier1"),
        ("r.embedding::halfvec", "tier2"),
        ("SELECT video_id\nFROM gym_video_feed", "prev_verdicts"),
        ("IN ('pending', 'accepted')", "enrich_targets"),
        ("v.tag AS genre", "scan_targets"),
        ("UPDATE gym_video_feed", "update_verdict"),
        ("failure_count = failure_count + 1", "bump_failure"),
        ("failure_count = 0", "reset_failure"),
        ("INSERT INTO video_rag", "insert_rag"),
        ("SET transcript", "cache_transcripts"),
        ("SET tag", "update_tags"),
        ("SET channel_avatar_url", "update_channel_avatar"),
        ("SET channel_url", "update_channel_url"),
        ("ARRAY_AGG(video_id ORDER BY video_id)", "handle_channels"),
        # Must precede channel_avatar_state: the backfill's target query also
        # aggregates with bool_or(channel_avatar_url ...).
        ("AS known_avatar", "avatar_targets"),
        ("bool_or(channel_avatar_url", "channel_avatar_state"),
        ("INSERT INTO video (", "upsert_video"),
        ("FROM video\nWHERE video_id = ANY(:ids)", "existing_videos"),
        ("INSERT INTO cost_log", "insert_cost"),
    ]
    for token, name in checks:
        if token in sql:
            return name
    if "INSERT INTO gym_video_feed" in sql:
        # Both are INSERT INTO gym_video_feed: the carry-forward is an
        # INSERT ... SELECT, the pending write is an INSERT ... VALUES.
        return "carry_forward" if "SELECT\n    gym_id" in sql else "insert_pending"
    raise AssertionError(f"unrouted SQL:\n{sql[:200]}")


class _FakeResult:
    def __init__(self, rows: list[dict]) -> None:
        self._rows = rows

    @property
    def rowcount(self) -> int:
        return len(self._rows)

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
        # Per-name queues that pop one value per call (for a read whose result
        # must change across calls, e.g. the scrape drain re-selecting due gyms).
        # Falls back to ``ones`` once a queue is exhausted / absent.
        self.seq: dict[str, list[dict | None]] = {}
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
        if self.seq.get(name):
            return self.seq[name].pop(0)
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


class FakeYouTube:
    """YouTube Data API client stand-in: programmable ``search`` / ``list_videos``
    / ``list_channels``.

    ``search_items`` maps a query → its ``search.list`` items; ``details`` maps a
    video id → its ``videos.list`` detail item; ``channels`` maps a channel id →
    its ``channels.list`` item. Records the queries searched and the id batches
    listed (videos and channels separately)."""

    def __init__(
        self,
        search_items: dict[str, list[dict]] | None = None,
        details: dict[str, dict] | None = None,
        channels: dict[str, dict] | None = None,
    ) -> None:
        self._search_items = search_items or {}
        self._details = details or {}
        self._channels = channels or {}
        self.searched: list[str] = []
        self.listed: list[list[str]] = []
        self.channels_listed: list[list[str]] = []

    async def search(
        self, query: str, *, max_results: int, language: str
    ) -> list[dict]:
        self.searched.append(query)
        return list(self._search_items.get(query, []))

    async def list_videos(self, video_ids: list[str]) -> list[dict]:
        self.listed.append(list(video_ids))
        return [self._details[v] for v in video_ids if v in self._details]

    async def list_channels(self, channel_ids: list[str]) -> list[dict]:
        self.channels_listed.append(list(channel_ids))
        return [self._channels[c] for c in channel_ids if c in self._channels]


class FakeTranscriptClient:
    """Batched transcript client stand-in: one ``fetch_batch`` run returns a canned
    transcript per requested video id (or None for a miss), recording every batch
    fetched (as an ordered id list) and the flat list of ids fetched.
    ``fail=True`` misses on every id (all-None, as a real error/timeout would)."""

    def __init__(
        self, transcripts: dict[str, str] | None = None, *, fail: bool = False
    ) -> None:
        self._transcripts = transcripts or {}
        self._fail = fail
        self.fetched: list[str] = []
        self.batches: list[list[str]] = []

    async def fetch_batch(self, video_ids: list[str]) -> dict[str, str | None]:
        self.batches.append(list(video_ids))
        self.fetched.extend(video_ids)
        if self._fail:
            return {vid: None for vid in video_ids}
        return {vid: self._transcripts.get(vid) for vid in video_ids}


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
