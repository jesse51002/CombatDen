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

from schema import FontOutput, FontSet, OverwriteSpecs
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
        seed: dict[str, FontOutput] | None = None,
        overwrite_specs: OverwriteSpecs | None = None,
    ) -> None:
        super().__init__(
            run_ctx,
            key=DependencyKind.FONT.value,
            deps=frozenset(),
            declared_slots={slot.id for slot in run_ctx.app.fonts},
            seed=seed,
            overwrite_specs=overwrite_specs,
        )
        self._selection = FontSelectionService(llm, catalog)

    async def run(self, *, model: str = FONT_MODEL) -> FontSet:
        """One LLM call resolves the dirty font slots; the catalog validates
        each pick inside the existing structured-output retry loop.

        Fresh run (empty seed): every slot is dirty and resolved. Reopen:
        regenerate only the dirty slots — those steered by ``overwrite_specs``
        or missing from the seed — showing the rest as fixed context, and keep
        every non-dirty slot's seeded pick verbatim. Nothing dirty ⇒ the seed
        is returned as-is, no LLM call."""
        dirty = self.dirty()
        self.regenerated = dirty
        if not dirty:
            return FontSet(fonts=dict(self.seed))  # type: ignore[arg-type]
        regenerated = await self._selection.resolve(
            self._run_ctx,
            model=model,
            only=dirty,
            fixed=self.seed,  # type: ignore[arg-type]
            overwrite_specs=self.overwrite_specs,
        )
        return FontSet(fonts={**self.seed, **regenerated.fonts})
