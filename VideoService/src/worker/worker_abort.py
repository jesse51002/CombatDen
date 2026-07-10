"""The cooperative-abort primitive shared by the tick and its drain loops.

One heartbeat task renews the worker's lock lease while a tick runs; if it loses
the lease it sets an ``asyncio.Event``. Every long drain (scan / enrich / scrape)
checks that flag between videos / batches / gyms via ``check_abort`` and stops by
raising ``WorkerAborted`` (another process may already own the work). Kept in its
own module so the service AND the stage classes can import it without a cycle.
"""

from __future__ import annotations

import asyncio


class WorkerAborted(Exception):
    """Raised inside a drain loop when the heartbeat lost the worker lock — the
    tick must stop."""


def check_abort(abort: asyncio.Event) -> None:
    """Raise ``WorkerAborted`` when the abort flag is set (a no-op otherwise)."""
    if abort.is_set():
        raise WorkerAborted("heartbeat lost the worker lock")
