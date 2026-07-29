"""RunRegistry — one run at a time: its live state, its log, its stream.

Three jobs, all keyed on one ``run_id``:

1. **Serialize globally.** Exactly one run is in flight at a time. The
   pipeline hits rate-limited LLM / image providers and concurrent runs get
   throttled (`.claude/skills/brand-brief/SKILL.md`), so a second launch is
   refused with ``RunInFlightError`` rather than queued — the UI can then
   say *which* run is already going. This guards the studio only: someone
   running `python -m src` in a terminal at the same time is not visible
   here and is not prevented.
2. **Keep durable state.** Every record is appended as one JSON line to
   ``.studio/runs/<run_id>.jsonl`` — outside every run directory, because a
   run's produced artifacts are never written to by anything but the
   pipeline. A log whose last line is not terminal is a crashed run, which
   is knowledge no ``output.yaml`` on disk can carry.
3. **Fan the records out.** Every subscriber replays from index 0 and then
   follows along, so a tab that opens late — or reconnects — misses
   nothing. That is why the records are kept as a list rather than pushed
   through a queue.

The registry is also the executor's ``ProgressSink`` (via ``RunSink``), so
the pipeline core stays transport-agnostic: it emits Pydantic events and
knows nothing about JSONL, SSE or HTTP.
"""

from __future__ import annotations

import asyncio
import logging
import re
from collections.abc import AsyncIterator
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

from pydantic import ValidationError

from src.executor.progress_event import ProgressEvent
from src.executor.progress_sink import ProgressSink
from src.studio.config import RUN_LOG_SUFFIX, settings
from src.studio.errors import RunInFlightError, UnknownRunError
from src.studio.schema.run_record import RunRecord, RunRecordKind
from src.studio.schema.run_snapshot import RunSnapshot
from src.studio.schema.run_status import RunStatus

logger = logging.getLogger(__name__)

# Run ids are `uuid4().hex`: 32 lowercase hex digits. Checked before the id
# is ever joined onto a path, so a request can't name a file outside
# `.studio/runs/`.
RUN_ID_PATTERN = re.compile(r"^[0-9a-f]{32}$")


def _now() -> str:
    """UTC, ISO-8601 — the timestamp on every record."""
    return datetime.now(timezone.utc).isoformat()


@dataclass
class _LiveRun:
    """One in-memory run: its identity, its records, and its waiters."""

    run_id: str
    app_id: str
    run_name: str
    started_at: str
    log_path: Path
    status: RunStatus = RunStatus.RUNNING
    finished_at: str | None = None
    error: str | None = None
    records: list[RunRecord] = field(default_factory=list)
    # Woken on every append and on settle; subscribers wait on it.
    condition: asyncio.Condition = field(default_factory=asyncio.Condition)


class RunSink(ProgressSink):
    """The executor's view of the registry: one run's event drain."""

    def __init__(self, registry: RunRegistry, run_id: str) -> None:
        self._registry = registry
        self._run_id = run_id

    async def emit(self, event: ProgressEvent) -> None:
        """Append one event. Never raises — a display concern must not
        abort a paid run (the ``ProgressSink`` contract)."""
        try:
            await self._registry.record(self._run_id, event)
        except Exception:  # noqa: BLE001 - a sink must never fail a run
            logger.warning(
                "dropping a progress event for run %s",
                self._run_id,
                exc_info=True,
            )


class RunRegistry:
    """In-memory run state over an append-only per-run JSONL log."""

    def __init__(self, runs_dir: Path) -> None:
        self._runs_dir = runs_dir
        self._live: dict[str, _LiveRun] = {}
        self._active_id: str | None = None
        # Guards the check-and-set that keeps runs serialized. Held only
        # across the reservation, never across the run itself.
        self._gate = asyncio.Lock()

    # --- launching -------------------------------------------------------

    async def open(self, *, app_id: str, run_name: str) -> RunSnapshot:
        """Reserve the single run slot and write the log's header line.

        Raises ``RunInFlightError`` when another run is already going.
        Returns the new run's snapshot (its ``run_id`` is what the caller
        watches).
        """
        async with self._gate:
            if self._active_id is not None:
                active = self._live[self._active_id]
                raise RunInFlightError(
                    active.run_id, active.app_id, active.run_name
                )
            run_id = uuid4().hex
            run = _LiveRun(
                run_id=run_id,
                app_id=app_id,
                run_name=run_name,
                started_at=_now(),
                log_path=self._runs_dir / f"{run_id}{RUN_LOG_SUFFIX}",
            )
            self._live[run_id] = run
            self._active_id = run_id
        await self._append(
            run,
            RunRecord(
                kind=RunRecordKind.LAUNCHED,
                index=0,
                at=run.started_at,
                run_id=run_id,
                app_id=app_id,
                run_name=run_name,
            ),
        )
        return self._snapshot_of(run)

    def sink(self, run_id: str) -> RunSink:
        """The ``ProgressSink`` to hand ``Pipeline.run()`` for this run."""
        return RunSink(self, run_id)

    # --- recording -------------------------------------------------------

    async def record(self, run_id: str, event: ProgressEvent) -> None:
        """Append one executor event to the run's stream."""
        run = self._require_live(run_id)
        await self._append(
            run,
            RunRecord(
                kind=RunRecordKind.PROGRESS,
                index=len(run.records),
                at=_now(),
                event=event,
            ),
        )

    async def settle(
        self, run_id: str, *, status: RunStatus, error: str | None = None
    ) -> None:
        """Close the run: write the terminal line and free the run slot.

        Idempotent-ish by construction — the launcher calls it exactly once,
        in a ``finally``-shaped path, so a crash between the last event and
        here is precisely the case the non-terminal log identifies.
        """
        run = self._require_live(run_id)
        run.status = status
        run.finished_at = _now()
        run.error = error
        await self._append(
            run,
            RunRecord(
                kind=RunRecordKind.SETTLED,
                index=len(run.records),
                at=run.finished_at,
                status=status,
                error=error,
            ),
        )
        async with self._gate:
            if self._active_id == run_id:
                self._active_id = None

    # --- reading ---------------------------------------------------------

    @property
    def active(self) -> RunSnapshot | None:
        """The run currently in flight, if any."""
        if self._active_id is None:
            return None
        return self._snapshot_of(self._live[self._active_id])

    async def snapshot(self, run_id: str) -> RunSnapshot:
        """The run's full state — from memory, else replayed from its log.

        A log that survived a studio restart still answers: its header line
        carries the identity, and a last line that is not terminal means the
        process died mid-run (``RunStatus.CRASHED``).
        """
        self._check_id(run_id)
        run = self._live.get(run_id)
        if run is not None:
            return self._snapshot_of(run)
        records = await asyncio.to_thread(self._read_log, run_id)
        return self._snapshot_of_records(run_id, records)

    async def stream(self, run_id: str) -> AsyncIterator[RunRecord]:
        """Every record from index 0, then each new one as it lands.

        Ends after the terminal record, so a client that closes on it never
        reconnects. A run that is not in memory is replayed from its log; if
        that log has no terminal line, a synthetic ``CRASHED`` terminal
        record is yielded (derived, never written) so the client still
        terminates.
        """
        self._check_id(run_id)
        run = self._live.get(run_id)
        if run is None:
            records = await asyncio.to_thread(self._read_log, run_id)
            for record in records:
                yield record
            if not records or not records[-1].terminal:
                yield RunRecord(
                    kind=RunRecordKind.SETTLED,
                    index=len(records),
                    at=_now(),
                    status=RunStatus.CRASHED,
                    error=(
                        "the run log has no terminal record — the studio "
                        "process died while this run was in flight"
                    ),
                )
            return

        cursor = 0
        while True:
            async with run.condition:
                while (
                    cursor >= len(run.records)
                    and run.status is RunStatus.RUNNING
                ):
                    await run.condition.wait()
                pending = run.records[cursor:]
                cursor += len(pending)
                done = not pending and run.status is not RunStatus.RUNNING
            for record in pending:
                yield record
            if done:
                return

    # --- internals -------------------------------------------------------

    async def _append(self, run: _LiveRun, record: RunRecord) -> None:
        """Add one record to the live list, persist it, wake the waiters.

        Memory first so a subscriber never blocks on disk, then the durable
        line, then the wake — the record is observable only once it is both
        in the list and on disk.
        """
        async with run.condition:
            run.records.append(record)
        await asyncio.to_thread(self._append_line, run.log_path, record)
        async with run.condition:
            run.condition.notify_all()

    @staticmethod
    def _append_line(path: Path, record: RunRecord) -> None:
        """One JSON object, one line, opened in append mode."""
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as handle:
            handle.write(record.model_dump_json() + "\n")

    def _read_log(self, run_id: str) -> list[RunRecord]:
        """Every parseable record in a run's durable log.

        A truncated final line (the classic crash-mid-write) is skipped
        with a warning rather than failing the read: the surviving records
        are exactly the evidence the caller wants.
        """
        path = self._runs_dir / f"{run_id}{RUN_LOG_SUFFIX}"
        if not path.is_file():
            raise UnknownRunError(f"no such run {run_id}")
        records: list[RunRecord] = []
        for line in path.read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            try:
                records.append(RunRecord.model_validate_json(line))
            except ValidationError:
                logger.warning(
                    "skipping an unparseable line in %s", path, exc_info=True
                )
        return records

    def _require_live(self, run_id: str) -> _LiveRun:
        run = self._live.get(run_id)
        if run is None:
            raise UnknownRunError(f"no live run {run_id}")
        return run

    @staticmethod
    def _check_id(run_id: str) -> None:
        """Reject anything that is not a ``uuid4().hex`` before it becomes
        a path (defence in depth against traversal)."""
        if not RUN_ID_PATTERN.match(run_id):
            raise UnknownRunError(f"malformed run id {run_id!r}")

    @staticmethod
    def _snapshot_of(run: _LiveRun) -> RunSnapshot:
        return RunSnapshot(
            run_id=run.run_id,
            app_id=run.app_id,
            run_name=run.run_name,
            status=run.status,
            started_at=run.started_at,
            finished_at=run.finished_at,
            error=run.error,
            records=list(run.records),
        )

    @staticmethod
    def _snapshot_of_records(
        run_id: str, records: list[RunRecord]
    ) -> RunSnapshot:
        """Rebuild a snapshot from a durable log alone (post-restart)."""
        header = next(
            (r for r in records if r.kind is RunRecordKind.LAUNCHED), None
        )
        if header is None:
            raise UnknownRunError(
                f"run {run_id}'s log has no launch record; it is unreadable"
            )
        last = records[-1]
        if last.terminal:
            status = last.status or RunStatus.FAILED
            finished_at: str | None = last.at
            error = last.error
        else:
            # No terminal line ⇒ the process died mid-run. This is the one
            # thing the log knows that the run directory cannot.
            status = RunStatus.CRASHED
            finished_at = None
            error = (
                "the run log has no terminal record — the studio process "
                "died while this run was in flight"
            )
        return RunSnapshot(
            run_id=run_id,
            app_id=header.app_id or "",
            run_name=header.run_name or "",
            status=status,
            started_at=header.at,
            finished_at=finished_at,
            error=error,
            records=records,
        )


_registry: RunRegistry | None = None


def run_registry() -> RunRegistry:
    """The process-wide registry. One per studio process — the single-run
    rule is only meaningful if every request sees the same one."""
    global _registry
    if _registry is None:
        _registry = RunRegistry(settings.runs_dir)
    return _registry
