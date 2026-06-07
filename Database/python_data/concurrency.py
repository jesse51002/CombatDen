"""Run a seed loop step across a small thread pool.

The seed makes many backend / Stripe round-trips that are individually slow
(a membership start can take 9-60s waiting on Stripe). Several of these loops
have no cross-item dependency, so running a handful at a time cuts wall-clock
sharply. ``run_concurrent`` maps a function over a list across a bounded pool,
**preserving input order** in the returned list and re-raising the first
exception (the seed should fail loudly, not swallow a broken row).

Safety note: the backend serializes billing ops per paying-parent family via a
non-reentrant lock with a 5s acquire timeout. So only dispatch items that touch
*disjoint* families to this helper (e.g. one family per item, or per-member work
that takes no membership lock). Two items hitting the same family concurrently
would race the lock and fail with a 409 — keep same-family work sequential
inside a single item.
"""

from __future__ import annotations

import threading
from collections.abc import Callable, Sequence
from concurrent.futures import ThreadPoolExecutor
from typing import TypeVar

import progress
from constants import SEED_WORKERS

T = TypeVar("T")
R = TypeVar("R")


class _Counter:
    """Thread-safe completion counter that prints a flushed progress line."""

    def __init__(self, total: int, label: str) -> None:
        self._total = total
        self._label = label
        self._done = 0
        self._lock = threading.Lock()

    def tick(self) -> None:
        with self._lock:
            self._done += 1
            progress.item(self._done, self._total, self._label)


def run_concurrent(
    items: Sequence[T],
    fn: Callable[[T], R],
    label: str,
    workers: int = SEED_WORKERS,
) -> list[R]:
    """Map ``fn`` over ``items`` across ``workers`` threads, order preserved.

    Prints a ``[done/total] label`` line as each item finishes. Re-raises the
    first exception any worker hits (after the pool drains). Returns ``[]`` for
    an empty input without spinning up a pool.
    """
    items = list(items)
    if not items:
        return []
    counter = _Counter(len(items), label)

    def _wrapped(item: T) -> R:
        result = fn(item)
        counter.tick()
        return result

    with ThreadPoolExecutor(max_workers=workers) as pool:
        # executor.map preserves input order and re-raises the first exception
        # when the result is consumed.
        return list(pool.map(_wrapped, items))
