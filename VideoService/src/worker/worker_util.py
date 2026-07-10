"""Small pure helpers shared across the worker's steps.

``vector_literal`` renders a float embedding as pgvector's text form (the funnel's
tier-2 probe and the enrich sweep's ``video_rag`` insert both bind it); ``chunks``
splits a sequence into fixed-size batches (the enrich sweep chunks its targets, the
scan sweep chunks a gym's candidates). Both lived duplicated in the step modules —
one home keeps a single implementation.
"""

from __future__ import annotations

from collections.abc import Iterator, Sequence
from typing import TypeVar

_T = TypeVar("_T")


def vector_literal(vector: list[float]) -> str:
    """A float list as the pgvector text form ``[f1,f2,...]`` (cast to ``vector`` /
    ``halfvec`` in SQL)."""
    return "[" + ",".join(repr(float(f)) for f in vector) + "]"


def chunks(seq: Sequence[_T], size: int) -> Iterator[list[_T]]:
    """Yield ``seq`` in lists of at most ``size``."""
    for start in range(0, len(seq), size):
        yield list(seq[start : start + size])
