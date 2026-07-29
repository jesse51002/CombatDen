"""ProgressEvent — what the executor reports while a run is in flight.

One tight unit: the event kind and the event itself. A run emits a stream
of these to an optional ``ProgressSink``
(``src/shared/interfaces/progress_sink.py``) so a caller can watch a run
happen instead of waiting for ``output.yaml``.

The event is deliberately **transport-agnostic**: it knows nothing about
HTTP, SSE, JSON framing or FastAPI. It is a plain Pydantic model the
executor hands to whatever sink it was given; a sink is free to log it,
queue it, or serialize it onto the wire.

Every field but ``kind`` is optional because one model covers six event
kinds. Which fields a kind carries:

- ``RUN_STARTED`` — ``app_id``, ``run_id``, ``total_levels``, ``total_nodes``
- ``LEVEL_STARTED`` — ``level``, ``level_nodes``, ``total_levels``
- ``NODE_STARTED`` — ``node``, ``image_slot``, ``level``
- ``NODE_FINISHED`` — ``node``, ``image_slot``, ``level``, ``ok=True``,
  ``elapsed_seconds``
- ``NODE_FAILED`` — the same plus ``ok=False`` and ``error``
- ``RUN_FINISHED`` — ``elapsed_seconds``, ``cost``, ``generated``

``image_slot`` is the field that makes a live gallery possible: the
executor sets it on the three node events **only** for the per-slot image
nodes (it is that slot's id), so a client knows a slot's
``final_images/<slot>.png`` has just landed on disk and can fetch it
immediately. Every other node key is a graph root (colour / font / text /
icon / category) and leaves it ``None``.
"""

from __future__ import annotations

import enum

from pydantic import BaseModel, ConfigDict


class ProgressEventKind(str, enum.Enum):
    """The six things a watched run reports."""

    RUN_STARTED = "run_started"
    LEVEL_STARTED = "level_started"
    NODE_STARTED = "node_started"
    NODE_FINISHED = "node_finished"
    NODE_FAILED = "node_failed"
    RUN_FINISHED = "run_finished"


class ProgressEvent(BaseModel):
    """One observation from an in-flight run."""

    model_config = ConfigDict(extra="forbid")

    kind: ProgressEventKind

    # --- run scope (RUN_STARTED / RUN_FINISHED) --------------------------
    app_id: str | None = None
    run_id: str | None = None
    total_levels: int | None = None
    total_nodes: int | None = None
    # Raw sum of every paid service's running cost at the end of the run.
    # Unrounded on purpose: the artifact's rounded ``RunCost`` is the
    # Writer's job, and a progress event is not the artifact.
    cost: float | None = None
    # The slot ids this pass actually (re)made (PipelineResult.generated).
    generated: list[str] | None = None

    # --- level scope (LEVEL_STARTED) -------------------------------------
    # 0-based index into ``nx.topological_generations``.
    level: int | None = None
    level_nodes: list[str] | None = None

    # --- node scope (NODE_STARTED / NODE_FINISHED / NODE_FAILED) ---------
    node: str | None = None
    # Set only for a per-slot image node: that slot's id (see module docstring).
    image_slot: str | None = None
    ok: bool | None = None
    # perf_counter wall-clock seconds. On a node event, that node's own time
    # measured from when it acquired the concurrency semaphore (when it
    # really started, not when the level did); on RUN_FINISHED, the whole run.
    elapsed_seconds: float | None = None
    error: str | None = None
