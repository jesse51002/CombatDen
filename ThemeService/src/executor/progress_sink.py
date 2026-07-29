"""ProgressSink — the async contract for watching a run in flight.

The executor's one outbound port for progress. It lives beside the
executor (not in ``src/shared/interfaces/``, which holds the *provider*
contracts — LLM, image generation, fonts, icons) because it is not a
provider: it is an observer the executor pushes to.

It is an interface, not a transport. An implementation may append to a
list, push onto a queue, or serialize onto an SSE stream — the pipeline
core neither knows nor cares, which is what keeps it transport-agnostic
(see ``CLAUDE.md`` → *Async everywhere*).

Passing a sink is optional. ``Pipeline.run()`` takes ``progress=None`` by
default and a run without a sink behaves exactly as it always has.

Implementations must not raise: an emit failure would abort a paid run
over a display concern. Swallow (and log) inside the sink.
"""

from __future__ import annotations

from abc import ABC, abstractmethod

from src.executor.progress_event import ProgressEvent


class ProgressSink(ABC):
    """Receive one run's progress events, in order (contract)."""

    @abstractmethod
    async def emit(self, event: ProgressEvent) -> None:
        """Record one event. Called from the executor's own task, in
        emission order. Must not raise and must not block."""
        raise NotImplementedError
