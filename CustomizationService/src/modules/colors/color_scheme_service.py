"""ColorSchemeService — owns the one structured LLM call that resolves
every colour slot of the brand's **colour scheme** from the brand brief.

The LLM is asked for the bare OKLCH + prose per slot; the deterministic
contract (chroma band, mode-appropriate text lightness, WCAG AA between
background and text) rides the existing ``complete_structured`` retry
loop via the ``model_validator(mode="after")`` on the per-request
response model. Failures are re-asked; everything in this file runs
after the contract has passed.

The service returns a typed ``LLMPalette`` (defined in
``color_models``) — the internal handoff to the correction and
derivation services downstream — rather than the final ``ColorPalette``
so each stage of the pipeline owns one concern.
"""

from __future__ import annotations

from pathlib import Path
from string import Template

from schema import ColorMode
from src.core.run_context import RunContext
from src.modules.colors.color_models import (
    LLMPalette,
    build_color_response_model,
)
from src.shared.interfaces.llm_client import LLMClient

COLOR_PROMPT_PATH = Path(__file__).parent / "prompts" / "color_palette_rule.md"

# Model for the one colour-scheme call. A per-call constant, not config:
# the model is a property of this call. Override via ``resolve(model=...)``
# in dev (bake-off scripts under ``scripts/``); production uses this default.
COLOR_MODEL = "anthropic/claude-sonnet-4-6"


class ColorSchemeService:
    """Builds the LLM prompt and runs the one structured call that
    resolves the brand's colour scheme."""

    def __init__(self, llm: LLMClient) -> None:
        self._llm = llm

    async def resolve(
        self, run_ctx: RunContext, *, model: str = COLOR_MODEL
    ) -> LLMPalette:
        """Run the colour LLM call; return the contract-clean schema.

        The per-request closed model is built per call so the LLM sees an
        explicit, required field for every slot id in this run's app
        (Anthropic strict structured output rejects open maps). The
        cross-slot contrast/sanity contract is the model_validator on
        that model — failures re-ride the existing retry loop, this
        function returns only when the contract is clean.
        """
        slot_ids = [slot.id for slot in run_ctx.app.colors]
        # roles + mode come from app.yaml / customization.yaml (never the
        # LLM); they drive the deterministic contract and ride through to
        # the correction + derivation services downstream.
        roles = {slot.id: slot.role for slot in run_ctx.app.colors}
        mode = run_ctx.cust.colors_direction.mode
        response_model = build_color_response_model(
            slot_ids, roles=roles, dark_mode=mode is ColorMode.DARK
        )
        messages = [{"role": "user", "content": self._build_prompt(run_ctx)}]
        resolved = await self._llm.complete_structured(
            messages, schema=response_model, model=model
        )
        # Flatten the closed dynamic model back into a plain dict so
        # downstream services don't have to know its per-request shape.
        colors = {sid: getattr(resolved, sid) for sid in slot_ids}
        return LLMPalette(mode=mode, roles=roles, colors=colors)

    @staticmethod
    def _build_prompt(run_ctx: RunContext) -> str:
        """Rule + brand brief + slot inventory, substituted into the one
        ``.md`` template (``safe_substitute`` tolerates a stray ``$``)."""
        template = COLOR_PROMPT_PATH.read_text(encoding="utf-8")
        design = run_ctx.cust.design_direction
        colors = run_ctx.cust.colors_direction
        inventory = "\n".join(
            f"- {slot.id}: {slot.description}"
            for slot in run_ctx.app.colors
        )
        return Template(template).safe_substitute(
            name=design.name,
            short=design.short_desc,
            long=design.long_desc,
            colour_direction=colors.description,
            dark_mode=colors.mode is ColorMode.DARK,
            slots=inventory,
        )
