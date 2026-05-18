"""CustomizationService — the shared parent of every customization module."""

from __future__ import annotations

from abc import ABC

from src.core.run_context import RunContext


class CustomizationService(ABC):
    """A customization module (colors, images, ...): shared run-context
    plumbing only.

    Every module's entrypoint is ``run`` and does the smallest atomic unit
    of work — colours resolve the whole palette (``run()``); images resolve
    a single image (``run(slot, palette)``). The executor owns iteration
    over slots, so modules never batch or manage concurrency themselves.
    """

    def __init__(self, run_ctx: RunContext | None = None) -> None:
        # Optional only so a module can be built for a sub-task that needs
        # no run context (e.g. ImageGenService for cutout validation
        # alone); every ``run`` path still requires it.
        self._run_ctx = run_ctx
