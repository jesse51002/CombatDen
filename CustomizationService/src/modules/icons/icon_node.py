"""IconNode — the icon graph node: resolve every icon slot to an SVG.

A level-0 sibling of ``ColorNode`` / ``FontNode`` / ``TextNode``: no
dependencies (icons are monochrome / ``currentColor`` so they need no
palette), runs in parallel with the other roots at the top of the DAG.

``run()`` is a thin composition of the module's three services, each of
which owns its own orchestration:

1. ``IconSetSelectionService.select`` — pick the best-fit set (call 1).
2. ``IconMatchingService.match`` — match every slot within that set and
   copy the matched SVGs into the run dir, returning the matched outputs
   plus the slots nothing fit (call 2).
3. ``IconGenerationService.resolve`` — author prompts for and generate an
   SVG per unmatched slot (call 3).

The node only merges the two halves into the ``IconSet``; the per-slot
copy / generation and their fail-soft handling live in the services.
"""

from __future__ import annotations

from schema import IconSet
from schema.output.icon_attribution import IconAttribution
from schema.output.icon_output import IconOutput
from src.core.run_context import RunContext
from src.modules.base import DependencyKind, Node
from src.modules.icons.icon_generation_service import IconGenerationService
from src.modules.icons.icon_matching_service import IconMatchingService
from src.modules.icons.icon_set_selection_service import (
    IconSetSelectionService,
)
from src.shared.interfaces.icon_set_catalog import (
    IconSetCatalog,
    IconSetCatalogEntry,
)
from src.shared.interfaces.image_generator import ImageGenerator
from src.shared.interfaces.llm_client import LLMClient


class IconNode(Node):
    """The icon node. ``run() -> IconSet``. No dependencies."""

    def __init__(
        self,
        run_ctx: RunContext,
        *,
        llm: LLMClient,
        catalog: IconSetCatalog,
        generator: ImageGenerator,
    ) -> None:
        super().__init__(
            run_ctx, key=DependencyKind.ICON.value, deps=frozenset()
        )
        self._selection = IconSetSelectionService(llm, catalog)
        self._matching = IconMatchingService(llm, catalog)
        self._generation = IconGenerationService(llm, generator)

    async def run(self) -> IconSet:
        """Select a set, match (+ copy) every slot, generate the misses,
        merge the two halves into the ``IconSet`` and attach any credit the
        chosen set's licence requires."""
        chosen = await self._selection.select(self._run_ctx)
        matched, unmatched = await self._matching.match(self._run_ctx, chosen)
        generated = await self._generation.resolve(
            self._run_ctx, chosen, unmatched
        )
        return IconSet(
            icons={**matched, **generated},
            attribution=self._attribution(chosen, matched),
        )

    @staticmethod
    def _attribution(
        chosen: IconSetCatalogEntry, matched: dict[str, IconOutput]
    ) -> IconAttribution | None:
        """Credit owed for this run, or ``None``.

        Emitted only when the chosen set declares an ``attribution`` notice
        (its licence requires a visible credit, e.g. CC BY 4.0) AND at least
        one icon was actually copied from it (``matched``). A run that fell
        back entirely to generated icons copied nothing, so owes no credit;
        permissive sets declare no notice and so produce ``None``.
        """
        if not matched or not chosen.attribution or not chosen.license:
            return None
        return IconAttribution(
            icon_set=chosen.id,
            name=chosen.name,
            license=chosen.license,
            notice=chosen.attribution,
        )
