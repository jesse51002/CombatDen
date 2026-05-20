"""ColorNode — the colour graph node: resolve every colour slot in one call.

The DAG root: no dependencies; every image node depends on it. ``run()``
is now a thin three-step orchestration over the three colour services:

1. ``ColorSchemeService`` — one structured LLM call, contract-clean.
2. ``ColorCorrectionService`` — deterministic clamps + checks.
3. ``ColorDerivationService`` — formats, six derivations, flat palette.

The node owns only the dependency-graph contract (key, deps). Constants
(``COLOR_MODEL``, prompt path) live in ``ColorSchemeService``; all the
math lives inside the services that use it.
"""

from __future__ import annotations

from schema import ColorPalette
from src.core.run_context import RunContext
from src.modules.base import DependencyKind, Node
from src.modules.colors.color_correction_service import ColorCorrectionService
from src.modules.colors.color_derivation_service import ColorDerivationService
from src.modules.colors.color_scheme_service import (
    COLOR_MODEL,
    ColorSchemeService,
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
        self._derivation = ColorDerivationService()

    async def run(self, *, model: str = COLOR_MODEL) -> ColorPalette:
        """Scheme → correction → derivation. One LLM call total; the
        rest is deterministic.
        """
        scheme = await self._scheme.resolve(self._run_ctx, model=model)
        corrected = self._correction.apply(scheme)
        return self._derivation.build(corrected)
