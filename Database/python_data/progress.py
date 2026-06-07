"""Tiny progress + timing helpers for the seed run.

The seed makes many sequential backend / Stripe round-trips. When one hangs, the
default phase-level prints give no clue which item stalled or how long anything
took. These helpers print flushed, per-item progress with the wall-clock time
each step took, so a slow or hung call is visible: the in-flight step is named
first, then its elapsed lands when it finishes OR when it raises (a timeout still
reports how long it ran before giving up).

``flush=True`` is load-bearing: when the seed's output is piped or redirected it
is block-buffered, so "print on each complete" would otherwise only appear once
the whole run ends.
"""

from __future__ import annotations

import time
from collections.abc import Iterator
from contextlib import contextmanager


def log(msg: str) -> None:
    """Print a line immediately (flushed)."""
    print(msg, flush=True)


def item(n: int, total: int, name: str, indent: str = "  ") -> None:
    """Print a ``[n/total] name`` per-item progress line (flushed)."""
    print(f"{indent}[{n}/{total}] {name}", flush=True)


@contextmanager
def timed_step(label: str, indent: str = "    ") -> Iterator[None]:
    """Time a step; print elapsed on success AND on failure, then re-raise.

    Prints ``-> label`` before running (so a hang names the in-flight step) and
    the elapsed when it finishes — or, if it raises (e.g. a ReadTimeout), the
    elapsed it ran before failing, so the slow call still reports its duration.
    """
    print(f"{indent}-> {label}", flush=True)
    start = time.perf_counter()
    try:
        yield
    except BaseException as exc:
        elapsed = time.perf_counter() - start
        print(
            f"{indent}FAIL {label} after {elapsed:.2f}s ({type(exc).__name__})",
            flush=True,
        )
        raise
    elapsed = time.perf_counter() - start
    print(f"{indent}OK   {label}  ({elapsed:.2f}s)", flush=True)
