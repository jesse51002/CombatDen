"""ColorGenService — the colour module: resolve colour slots in one proxy call."""

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


class ColorGenService(CustomizationService):
    """The colour module. ``run() -> ColorPalette``."""

    def __init__(self, run_ctx: RunContext, *, llm: LLMClient) -> None:
        super().__init__(run_ctx)
        self._llm = llm

    async def run(self) -> ColorPalette:
        """Resolve every colour slot; return the ``ColorPalette`` model.

        The wire schema is a per-request closed model so Pydantic validates
        the response accurately; the result is flattened back into the
        ``ColorPalette`` map.
        """
        messages = [{"role": "user", "content": self._build_prompt()}]
        slot_ids = [slot.id for slot in self._run_ctx.app.colors]
        response_model = build_color_response_model(slot_ids)
        resolved = await self._llm.complete_structured(
            messages,
            schema=response_model,
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
