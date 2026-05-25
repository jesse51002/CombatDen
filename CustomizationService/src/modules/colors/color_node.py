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

from schema import ColorMode, ColorPalette, ColorRole, OverwriteSpecs
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

    def __init__(
        self,
        run_ctx: RunContext,
        *,
        llm: LLMClient,
        seed: dict[str, ColorOutput] | None = None,
        overwrite_specs: OverwriteSpecs | None = None,
    ) -> None:
        super().__init__(
            run_ctx,
            key=DependencyKind.COLOR.value,
            deps=frozenset(),
            declared_slots={slot.id for slot in run_ctx.app.colors},
            seed=seed,
            overwrite_specs=overwrite_specs,
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

        Fresh run (empty seed): every slot is dirty and resolved. Reopen: only
        the dirty slots — steered by ``overwrite_specs`` or missing from the
        seed — are re-picked (the LLM call is scoped to them and shown the rest
        as fixed context); every non-dirty slot's ``ColorOutput`` is kept
        verbatim, so the palette stays internally consistent and nothing keyed
        to the untouched colours shifts. A fully-seeded colour node (nothing
        dirty) reassembles its palette from the seed with no LLM call."""
        dirty = self.dirty()
        self.regenerated = dirty
        if not dirty:
            return self._assemble_from_seed()
        scheme = await self._scheme.resolve(
            self._run_ctx,
            model=model,
            only=dirty,
            fixed=self.seed,  # type: ignore[arg-type]
            overwrite_specs=self.overwrite_specs,
        )
        schema = self._correction.apply(scheme)
        surfaces = self._surfaces.compute(
            canvas=schema.canvas, text=schema.text, dark_mode=schema.dark_mode
        )
        colors: dict[str, ColorOutput] = {}
        for sid in schema.colors:
            if sid not in dirty:
                colors[sid] = self.seed[sid]  # type: ignore[assignment]
                continue
            expanded = self._derivation.expand(
                schema.colors[sid],
                role=schema.roles[sid],
                canvas=schema.canvas,
                text=schema.text,
                dark_mode=schema.dark_mode,
                surfaces=surfaces,
            )
            colors[sid] = expanded.model_copy(
                update={"overwrite_specs": self.overwrite_specs}
            )
        return ColorPalette(
            mode=schema.mode,
            colors=colors,
            palette=self.create_palette(colors, surfaces),
        )

    def _assemble_from_seed(self) -> ColorPalette:
        """Rebuild the full ``ColorPalette`` from the seeded per-slot colours,
        no LLM call: the surfaces and flat palette are deterministic from the
        base colours, so a fully-seeded node reproduces its palette exactly."""
        colors: dict[str, ColorOutput] = {
            slot.id: self.seed[slot.id]  # type: ignore[misc]
            for slot in self._run_ctx.app.colors
        }
        roles = {slot.id: slot.role for slot in self._run_ctx.app.colors}
        bg_id = next(
            sid for sid, r in roles.items() if r is ColorRole.BACKGROUND
        )
        text_id = next(
            sid for sid, r in roles.items() if r is ColorRole.TEXT
        )
        dark_mode = self._run_ctx.cust.colors_direction.mode is ColorMode.DARK
        surfaces = self._surfaces.compute(
            canvas=colors[bg_id].color.oklch,
            text=colors[text_id].color.oklch,
            dark_mode=dark_mode,
        )
        return ColorPalette(
            mode=self._run_ctx.cust.colors_direction.mode,
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
