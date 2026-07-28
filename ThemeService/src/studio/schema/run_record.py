"""RunRecord — one line of a run's append-only log, and the SSE frame.

One tight unit: the record kind and the record. A launched run writes one
JSON object per line to ``.studio/runs/<run_id>.jsonl`` and hands the same
objects, in the same order, to every SSE subscriber. The log IS the event
stream — replayed from index 0 on connect, so a tab that opens late or
reconnects misses nothing.

A log reads as exactly three phases:

1. one ``LAUNCHED`` header — what was launched (this is the only place the
   app id and run name are recorded, and it is written *before* the
   pipeline starts, so a run that dies during graph build is still
   identifiable),
2. zero or more ``PROGRESS`` lines, each wrapping one executor
   ``ProgressEvent`` verbatim,
3. one ``SETTLED`` terminal line — succeeded or failed, with the error.

**A log whose last line is not ``SETTLED`` is a crashed run.** That is the
whole reason the log exists rather than inferring done-ness from an
``output.yaml`` on disk.
"""

from __future__ import annotations

import enum

from pydantic import BaseModel, ConfigDict

from src.executor.progress_event import ProgressEvent
from src.studio.schema.run_status import RunStatus


class RunRecordKind(str, enum.Enum):
    """The three line kinds, in the order they appear."""

    LAUNCHED = "launched"
    PROGRESS = "progress"
    SETTLED = "settled"


class RunRecord(BaseModel):
    """One append-only line — and one SSE frame's payload.

    Every field but ``kind``/``index``/``at`` is optional because one model
    covers all three line kinds. Which fields a kind carries:

    - ``LAUNCHED`` — ``run_id``, ``app_id``, ``run_name``
    - ``PROGRESS`` — ``event``
    - ``SETTLED`` — ``status`` (succeeded / failed) and, on a failure,
      ``error``

    ``index`` is the 0-based position in this run's stream; it is also the
    SSE frame's ``id:``.
    """

    model_config = ConfigDict(extra="forbid")

    kind: RunRecordKind
    index: int
    # UTC, ISO-8601. Human-readable in the log, orderable, and enough for a
    # UI to show when each step happened.
    at: str

    # --- LAUNCHED --------------------------------------------------------
    run_id: str | None = None
    app_id: str | None = None
    run_name: str | None = None

    # --- PROGRESS --------------------------------------------------------
    event: ProgressEvent | None = None

    # --- SETTLED ---------------------------------------------------------
    status: RunStatus | None = None
    error: str | None = None

    @property
    def terminal(self) -> bool:
        """Whether this record ends the stream (nothing follows it)."""
        return self.kind is RunRecordKind.SETTLED
