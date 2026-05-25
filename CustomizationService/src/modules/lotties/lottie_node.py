"""LottieNode — one lottie graph node: resolve a single lottie slot.

One instance per lottie slot (the registry builds the list; the executor
schedules them). Selective, not generative: it picks ONE preset from the
global library and maps that preset's regions to palette roles — it never
generates Lottie JSON and writes NO artifact to the run dir, only a
reference to the library preset plus a role-name recolour map.

``color`` is an automatic dependency (CALL 2 needs the palette
vocabulary). A reveal slot also declares ``depends_on`` an image slot;
that image's resolved output arrives via ``inputs`` and its prompt is fed
to the selection call. Two atomic haiku calls compose the slot — select,
then recolour-map — the way ``ColorNode`` chains its sub-services.
"""

from __future__ import annotations

from schema.lottie_library import LottiePreset
from schema.lottie_type import LottieType
from schema.output.image_output import ImageOutput
from schema.output.lottie_output import LottieOutput
from schema.slots import LottieSlot
from src.core.run_context import RunContext
from src.modules.base import DependencyKind, Node
from src.modules.lotties.lottie_library import LottiePresetLibrary
from src.modules.lotties.lottie_recolor_service import LottieRecolorService
from src.modules.lotties.lottie_selection_service import LottieSelectionService
from src.shared.interfaces.llm_client import LLMClient


class LottieNode(Node):
    """One lottie node, atomic per slot: ``run() -> LottieOutput``.

    ``slot`` and ``deps`` are construction state; ``color`` (the palette)
    and, for a reveal slot, the revealed image arrive via ``inputs`` set
    by the executor just before ``run()``.
    """

    def __init__(
        self,
        run_ctx: RunContext,
        *,
        slot: LottieSlot,
        deps: frozenset[str],
        llm: LLMClient,
        library: LottiePresetLibrary,
        seed: dict[str, LottieOutput] | None = None,
        overwrite_specs: str = "",
    ) -> None:
        super().__init__(
            run_ctx,
            key=slot.id,
            deps=deps,
            declared_slots={slot.id},
            seed=seed,
            overwrite_specs=overwrite_specs,
        )
        self._slot = slot
        self._library = library
        self._selection = LottieSelectionService(llm)
        self._recolor = LottieRecolorService(llm)

    async def run(self) -> LottieOutput:
        """Resolve this slot: select a preset, then map its regions to
        palette roles. Trusted fields (file, display name, insertion
        point) are lifted off the chosen preset, never from the LLM.

        A per-slot node: if this slot is seeded and not overridden (nothing
        dirty), the seeded output is returned verbatim — no LLM calls. Else it
        is regenerated, with any ``overwrite_specs`` steering the selection."""
        dirty = self.dirty()
        self.regenerated = dirty
        if not dirty:
            return self.seed[self._slot.id]  # type: ignore[return-value]
        palette = self.inputs[DependencyKind.COLOR.value]
        revealed: ImageOutput | None = (
            self.inputs[self._slot.depends_on]  # type: ignore[assignment]
            if self._slot.depends_on is not None
            else None
        )
        candidates = self._library.candidates(self._slot.required_type)
        preset: LottiePreset = await self._selection.resolve(
            self._run_ctx,
            slot=self._slot,
            candidates=candidates,
            revealed=revealed,
            overwrite_specs=self.overwrite_specs,
        )
        region_roles = await self._recolor.resolve(
            self._run_ctx, preset=preset, palette=palette
        )
        is_reveal = self._slot.required_type is LottieType.REVEAL
        return LottieOutput(
            preset_id=preset.id,
            preset_file=preset.file,
            display_name=preset.display_name,
            region_roles=region_roles,
            reveals=self._slot.depends_on,
            insertion_point=preset.insertion_point if is_reveal else None,
            overwrite_specs=self.overwrite_specs,
        )
