"""Executor graph primitives: ``DependencyKind`` and the ``Node`` base.

Sub-services (the small atomic calls a node composes — complexity, style,
background) have no shared base: each takes only what it uses. Graph
nodes extend ``Node``.
"""

from __future__ import annotations

import enum
from abc import ABC, abstractmethod

from pydantic import BaseModel

from schema import OverwriteSpecs
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

    Reopen-time steering (the ``regen`` / ``expand`` scripts) rides three
    construction fields:

    - ``declared_slots`` — every slot id this node resolves (a per-slot node
      owns just its own id; an atomic node owns its whole inventory).
    - ``seed`` — the preserved slots' per-item outputs (``{slot_id: output}``)
      from the run being reopened: the fixed context a partial regeneration
      shows the model and copies untouched slots from verbatim. **The seed is
      the sole control of what's regenerated**: any declared slot absent from
      it is re-made; to re-roll a slot, a caller simply leaves it out.
    The call's single ``OverwriteSpecs`` (the free-text ``specs`` plus optional
    per-module extras) is **not** a construction field — it rides on the
    ``RunContext`` (``run_ctx.overwrite_specs``) and is surfaced here as
    ``self.overwrite_specs`` for convenience, so a node still stamps it onto
    every slot it re-makes and reads any extras it cares about (the image node,
    ``image_to_image``) without threading a parameter. One per run; an empty
    default on a plain fill/full run.

    ``dirty()`` is just ``declared_slots - seed`` — what to (re)generate. Both
    default empty, so a fresh full run has an empty seed ⇒ every slot
    dirty ⇒ a normal full generation. ``regenerated`` is the set a node's
    ``run()`` records as the slots it actually re-made (the executor unions
    these for the ledger).
    """

    def __init__(
        self,
        run_ctx: RunContext | None,
        *,
        key: str,
        deps: frozenset[str],
        declared_slots: set[str] | None = None,
        seed: dict[str, BaseModel] | None = None,
    ) -> None:
        self._run_ctx = run_ctx
        self.key = key
        self.deps = deps
        self.inputs: dict[str, BaseModel] = {}
        self.declared_slots: set[str] = declared_slots or set()
        self.seed: dict[str, BaseModel] = seed or {}
        # Sourced from the run context (one steering object per run); a node
        # constructed without a context falls back to empty steering.
        self.overwrite_specs: OverwriteSpecs = (
            run_ctx.overwrite_specs if run_ctx is not None else OverwriteSpecs()
        )
        self.regenerated: set[str] = set()

    def dirty(self) -> set[str]:
        """The slots this node will (re)generate: every declared slot absent
        from the seed. A fresh run (empty seed) makes every slot dirty; a
        reopen re-makes only the slots the caller left out of the seed."""
        return self.declared_slots - set(self.seed)

    @abstractmethod
    async def run(self) -> BaseModel:
        """Resolve this node; return its single typed output model."""
        raise NotImplementedError
