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

from schema import ColorMode, ColorRole
from schema.output.color_output import ColorOutput
from src.core.run_context import RunContext
from src.modules.colors.color_models import (
    LLMPalette,
    LLMSlotResponse,
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
        self,
        run_ctx: RunContext,
        *,
        model: str = COLOR_MODEL,
        only: set[str] | None = None,
        fixed: dict[str, ColorOutput] | None = None,
    ) -> LLMPalette:
        """Run the colour LLM call; return the contract-clean FULL schema.

        The per-request closed model is built per call so the LLM sees an
        explicit, required field for every slot id requested (Anthropic
        strict structured output rejects open maps). The cross-slot
        contrast/sanity contract is the model_validator on that model —
        failures re-ride the existing retry loop, this function returns
        only when the contract is clean.

        ``only`` scopes the LLM call to a subset of slots (a partial regen);
        ``fixed`` is the prior ``ColorOutput`` per slot, used both as the
        fixed background/text context the AA contract checks against and to
        reconstruct the non-regenerated slots so the returned ``LLMPalette``
        is always the *full* base map (the downstream correction/surfaces
        steps need every slot). The run's steering
        (``run_ctx.overwrite_specs``) is folded into the prompt. With ``only``/
        ``fixed`` unset, every slot is resolved (full run).
        """
        declared = [slot.id for slot in run_ctx.app.colors]
        # roles + mode come from app.yaml / customization.yaml (never the
        # LLM); they drive the deterministic contract and ride through to
        # the correction + derivation services downstream.
        roles = {slot.id: slot.role for slot in run_ctx.app.colors}
        mode = run_ctx.cust.colors_direction.mode
        target_ids = sorted(only) if only is not None else declared
        fixed = fixed or {}

        bg_id = next(
            (sid for sid, r in roles.items() if r is ColorRole.BACKGROUND),
            None,
        )
        text_id = next(
            (sid for sid, r in roles.items() if r is ColorRole.TEXT), None
        )
        fixed_bg = (
            fixed[bg_id].color.oklch
            if bg_id and bg_id not in target_ids and bg_id in fixed
            else None
        )
        fixed_text = (
            fixed[text_id].color.oklch
            if text_id and text_id not in target_ids and text_id in fixed
            else None
        )

        response_model = build_color_response_model(
            target_ids,
            roles=roles,
            dark_mode=mode is ColorMode.DARK,
            fixed_bg=fixed_bg,
            fixed_text=fixed_text,
        )
        messages = [
            {
                "role": "user",
                "content": self._build_prompt(
                    run_ctx,
                    target_ids=target_ids,
                    fixed=fixed,
                ),
            }
        ]
        resolved = await self._llm.complete_structured(
            messages, schema=response_model, model=model
        )
        picks = {sid: getattr(resolved, sid) for sid in target_ids}
        # Assemble the FULL base map in declared order: regenerated slots
        # from the LLM, the rest reconstructed from their prior ColorOutput.
        colors: dict[str, LLMSlotResponse] = {}
        for sid in declared:
            if sid in picks:
                colors[sid] = picks[sid]
            elif sid in fixed:
                prior = fixed[sid]
                colors[sid] = LLMSlotResponse(
                    oklch=prior.color.oklch,
                    display_name=prior.display_name,
                    description=prior.description,
                )
        return LLMPalette(mode=mode, roles=roles, colors=colors)

    @staticmethod
    def _build_prompt(
        run_ctx: RunContext,
        *,
        target_ids: list[str],
        fixed: dict[str, ColorOutput],
    ) -> str:
        """Rule + brand brief + fixed-context + the slots to (re)pick,
        substituted into the one ``.md`` template (``safe_substitute``
        tolerates a stray ``$``). The run's steering note (instruction +
        rejected attempts) is appended over the slots being picked; fixed
        slots are listed as harmony context."""
        template = COLOR_PROMPT_PATH.read_text(encoding="utf-8")
        design = run_ctx.cust.design_direction
        colors = run_ctx.cust.colors_direction
        desc = {slot.id: slot.description for slot in run_ctx.app.colors}
        lines = [f"- {sid}: {desc.get(sid, '')}" for sid in target_ids]
        note = run_ctx.overwrite_specs.prompt_note()
        if note:
            lines.append(f"\n{note}")
        inventory = "\n".join(lines)
        fixed_lines = [
            f"- {sid}: {co.color.oklch!s} — {co.display_name}"
            for sid, co in fixed.items()
            if sid not in target_ids
        ]
        fixed_context = (
            "\n".join(fixed_lines)
            if fixed_lines
            else "(none — fresh palette)"
        )
        return Template(template).safe_substitute(
            name=design.name,
            short=design.short_desc,
            long=design.long_desc,
            colour_direction=colors.description,
            dark_mode=colors.mode is ColorMode.DARK,
            slots=inventory,
            fixed_context=fixed_context,
        )
