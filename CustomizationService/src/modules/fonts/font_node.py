"""FontNode — the font graph node: pick a Google Font for every font slot.

A level-0 sibling of ``ColorNode``: no dependencies, runs in parallel
with the colour root at the top of the DAG. Both spring from the brand
brief and don't need each other.

``run()`` is a thin one-step delegation to ``FontSelectionService`` —
fonts have no math step (no contrast / no derivations), so the
selection IS the resolution. The node only owns the dependency-graph
contract (key, deps); constants (``FONT_MODEL``, prompt path) live in
the selection service.
"""

from __future__ import annotations

from schema import FontSet
from src.core.run_context import RunContext
from src.modules.base import DependencyKind, Node
from src.modules.fonts.font_selection_service import (
    FONT_MODEL,
    FontSelectionService,
)
from src.shared.interfaces.google_fonts_catalog import GoogleFontsCatalog
from src.shared.interfaces.llm_client import LLMClient


class FontNode(Node):
    """The font node. ``run() -> FontSet``. No dependencies."""

    def __init__(
        self,
        run_ctx: RunContext,
        *,
        llm: LLMClient,
        catalog: GoogleFontsCatalog,
    ) -> None:
        super().__init__(
            run_ctx, key=DependencyKind.FONT.value, deps=frozenset()
        )
        self._selection = FontSelectionService(llm, catalog)

    async def run(self, *, model: str = FONT_MODEL) -> FontSet:
        """One LLM call resolves every font slot; the catalog validates
        each pick inside the existing structured-output retry loop."""
        return await self._selection.resolve(self._run_ctx, model=model)
