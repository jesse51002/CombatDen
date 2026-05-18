"""ColorGenService — the colour module: resolve colour slots in one LLM call."""

from __future__ import annotations

import logging
from pathlib import Path
from string import Template

from src.core.run_context import RunContext
from src.modules.base import CustomizationService
from src.modules.colors.color_models import (
    ColorPalette,
    build_color_response_model,
)
from src.shared.interfaces.llm_client import LLMClient

logger = logging.getLogger(__name__)

COLOR_PROMPT_PATH = Path(__file__).parent / "prompts" / "color_palette_rule.md"

# Model for the one colour-palette call. A per-call constant, not config:
# the model is a property of this call. Override `run(model=...)` in dev
# (bake-off scripts under `scripts/`); production uses this default.
COLOR_MODEL = "anthropic/claude-haiku-4-5-20251001"


class ColorGenService(CustomizationService):
    """The colour module. ``run() -> ColorPalette``."""

    def __init__(self, run_ctx: RunContext, *, llm: LLMClient) -> None:
        super().__init__(run_ctx)
        self._llm = llm

    async def run(self, *, model: str = COLOR_MODEL) -> ColorPalette:
        """Resolve every colour slot; return the ``ColorPalette`` model.

        The wire schema is a per-request closed model so Pydantic validates
        the response accurately; the result is flattened back into the
        ``ColorPalette`` map. ``model`` defaults to the module constant;
        override it in dev to compare models.
        """
        messages = [{"role": "user", "content": self._build_prompt()}]
        slot_ids = [slot.id for slot in self._run_ctx.app.colors]
        # roles + dark_mode come from app.yaml / customization.yaml (never
        # the LLM); they drive the deterministic contract on the wire model.
        roles = {slot.id: slot.role for slot in self._run_ctx.app.colors}
        dark_mode = self._run_ctx.cust.colors_direction.dark_mode
        response_model = build_color_response_model(
            slot_ids, roles=roles, dark_mode=dark_mode
        )
        resolved = await self._llm.complete_structured(
            messages,
            schema=response_model,
            model=model,
        )
        return ColorPalette(
            colors={slot_id: getattr(resolved, slot_id) for slot_id in slot_ids}
        )

    def _build_prompt(self) -> str:
        """Rule + brand brief + slot inventory, substituted into the one
        ``.md`` template (``safe_substitute`` tolerates a stray ``$``)."""
        template = COLOR_PROMPT_PATH.read_text(encoding="utf-8")
        design = self._run_ctx.cust.design_direction
        colors = self._run_ctx.cust.colors_direction
        inventory = "\n".join(
            f"- {slot.id}: {slot.description}" for slot in self._run_ctx.app.colors
        )
        return Template(template).safe_substitute(
            name=design.name,
            short=design.short_desc,
            long=design.long_desc,
            colour_direction=colors.description,
            dark_mode=colors.dark_mode,
            slots=inventory,
        )
