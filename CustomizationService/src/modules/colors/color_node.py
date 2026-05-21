"""ColorNode — the colour graph node: resolve every colour slot in one call.

The DAG root: no dependencies; every image node depends on it. ``run()``
orchestrates the colour services and assembles the final ``ColorPalette``:

1. ``ColorSchemeService`` — one structured LLM call, contract-clean.
2. ``ColorCorrectionService`` — the deterministic background-L clamp.
3. ``ColorSurfaceService`` — the run-wide shared surfaces (card/popup/divider).
4. ``ColorDerivationService`` — atomic; expands ONE colour, called per slot.
5. assemble the flat recommendation palette (the node's own glue).

The node owns iteration (one colour subsystem, one LLM result → many
colours) and the final aggregation; the services each own a single
indivisible piece. Constants (``COLOR_MODEL``, prompt path) live in
``ColorSchemeService``.
"""

from __future__ import annotations

from schema import ColorPalette
from schema.output.color_output import ColorOutput
from schema.output.color_value import ColorValue
from schema.output.derivations import Derivations
from src.core.run_context import RunContext
from src.modules.base import DependencyKind, Node
from src.modules.colors.color_correction_service import ColorCorrectionService
from src.modules.colors.color_derivation_service import ColorDerivationService
from src.modules.colors.color_models import LLMPalette
from src.modules.colors.color_scheme_service import (
    COLOR_MODEL,
    ColorSchemeService,
)
from src.modules.colors.color_surface_service import (
    ColorSurfaceService,
    SharedSurfaces,
)
from src.shared.interfaces.llm_client import LLMClient


class ColorNode(Node):
    """The colour node. ``run() -> ColorPalette``. No dependencies."""

    def __init__(self, run_ctx: RunContext, *, llm: LLMClient) -> None:
        super().__init__(
            run_ctx, key=DependencyKind.COLOR.value, deps=frozenset()
        )
        self._scheme = ColorSchemeService(llm)
        self._correction = ColorCorrectionService()
        self._surfaces = ColorSurfaceService()
        self._derivation = ColorDerivationService()

    async def run(self, *, model: str = COLOR_MODEL) -> ColorPalette:
        """The colour orchestration, one step per line:

        1. scheme (the one LLM call) → contract-clean ``LLMPalette``
        2. correction → background-L clamp
        3. surfaces → the run-wide shared card/popup/divider
        4. derivation → expand each slot atomically into a ``ColorOutput``
        5. create_palette → the flat recommendation dict

        Only step 1 is async / paid; the rest is deterministic.
        """
        scheme = await self._scheme.resolve(self._run_ctx, model=model)
        schema = self._correction.apply(scheme)
        surfaces = self._surfaces.compute(
            canvas=schema.canvas, text=schema.text, dark_mode=schema.dark_mode
        )
        colors = {
            sid: self._derivation.expand(
                schema.colors[sid],
                role=schema.roles[sid],
                canvas=schema.canvas,
                text=schema.text,
                dark_mode=schema.dark_mode,
                surfaces=surfaces,
            )
            for sid in schema.colors
        }
        return ColorPalette(
            mode=schema.mode,
            colors=colors,
            palette=self.create_palette(colors, surfaces),
        )

    @staticmethod
    def create_palette(
        colors: dict[str, ColorOutput], surfaces: SharedSurfaces
    ) -> dict[str, ColorValue]:
        """Build the flat recommendation palette from the expanded colours
        and the shared surfaces.

        Order matters (the "no original gets overwritten" invariant):
        1. per-colour derivations flattened as ``<slot>_<deriv>``
           (``Derivations.model_fields`` is the source of truth for the
           derivation names),
        2. shared surfaces (``card``, ``popup``, ``divider``),
        3. base slot colours LAST — a derivation-key collision with a
           base slot id falls to the base.
        """
        palette: dict[str, ColorValue] = {}
        for slot_id, color in colors.items():
            for deriv_name in Derivations.model_fields:
                palette[f"{slot_id}_{deriv_name}"] = getattr(
                    color.derivations, deriv_name
                )
        palette["card"] = surfaces.card
        palette["popup"] = surfaces.popup
        palette["divider"] = surfaces.divider
        for slot_id, color in colors.items():
            palette[slot_id] = color.color
        return palette
