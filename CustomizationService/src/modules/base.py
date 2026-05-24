"""Executor graph primitives: ``DependencyKind`` and the ``Node`` base.

Sub-services (the small atomic calls a node composes — complexity, style,
background) have no shared base: each takes only what it uses. Graph
nodes extend ``Node``.
"""

from __future__ import annotations

import enum
from abc import ABC, abstractmethod

from pydantic import BaseModel

from src.core.run_context import RunContext


class DependencyKind(str, enum.Enum):
    """Executor-owned, frozen dependency keys.

    Never appears in any YAML / ``Output`` / schema: the executor injects
    ``COLOR`` onto every image node so the engine treats the colour root
    like any other dependency. ``FONT``, ``TEXT`` and ``ICON`` are here
    for the same keyspace reason — no node implicitly depends on any of
    them today, but each root node still needs a stable graph key and an
    image slot named ``font`` / ``text`` / ``icon`` would shadow it if a
    future module ever depended on it. New executor-defined dependency
    kinds (never user slot ids) go here.
    """

    COLOR = "color"
    FONT = "font"
    TEXT = "text"
    ICON = "icon"


class Node(ABC):
    """A graph node: a customization unit the executor schedules.

    ``key`` and ``deps`` are set at construction; the executor copies the
    resolved outputs of this node's dependencies into ``inputs`` just
    before calling ``run()`` (each node instance runs exactly once per
    pipeline run, so the pre-run mutation is safe). ``run()`` takes no
    positional parameters and returns exactly one Pydantic model — the
    engine stays domain-blind.
    """

    def __init__(
        self, run_ctx: RunContext | None, *, key: str, deps: frozenset[str]
    ) -> None:
        self._run_ctx = run_ctx
        self.key = key
        self.deps = deps
        self.inputs: dict[str, BaseModel] = {}

    @abstractmethod
    async def run(self) -> BaseModel:
        """Resolve this node; return its single typed output model."""
        raise NotImplementedError
