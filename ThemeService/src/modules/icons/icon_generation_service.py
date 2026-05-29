"""IconGenerationService — the icon module's fallback path, end to end:
author Recraft prompts for the unmatched slots (one batch LLM call), then
generate one SVG per slot and write it into the run dir.

Call 3 of the icon module's three. Owns its whole half of the resolution
via ``resolve``: the batch prompt-authoring call, the per-slot Recraft
generation, and the resolved generated ``IconOutput``s. Separate from
matching and injected into ``IconNode`` at construction (modularity: the
low-level provider client — an ``ImageGenerator`` / Recraft — is swappable
behind this service, and this service is swappable behind the node).

A slot whose generation fails is dropped fail-soft (logged); the rest
still resolve.

TODO(long-term): cache generated SVGs back into the matched/chosen icon
set so an identical (set, slot concept) generation is reused across runs
instead of re-billed to Recraft every time.
"""

from __future__ import annotations

import logging
from pathlib import Path
from string import Template

from schema import IconOutput, IconSlot
from src.core.run_context import RunContext
from src.modules.icons.icon_models import LLMIconPrompt, build_icon_prompt_model
from src.shared.interfaces.icon_set_catalog import IconSetCatalogEntry
from src.shared.interfaces.image_generator import ImageGenerator
from src.shared.interfaces.llm_client import LLMClient

logger = logging.getLogger(__name__)

ICON_PROMPT_RULE_PATH = Path(__file__).parent / "prompts" / "icon_prompt_rule.md"

# Model for the batch prompt-authoring call. Haiku, per the owner: cheap
# and plenty for turning a slot description + brand vibe into a Recraft
# prompt. A per-call constant, not config.
ICON_PROMPT_MODEL = "anthropic/claude-haiku-4-5"

# Recraft's own model id, sent in the generation request body. Recraft is
# a direct (non-litellm) client, so this carries no provider prefix.
RECRAFT_MODEL = "recraftv4_1_utility_vector"


class IconGenerationService:
    """Authors Recraft prompts for unmatched icon slots (one batch call)
    and generates one SVG per slot via the injected ``ImageGenerator``."""

    def __init__(self, llm: LLMClient, generator: ImageGenerator) -> None:
        self._llm = llm
        self._generator = generator

    async def resolve(
        self,
        run_ctx: RunContext,
        chosen: IconSetCatalogEntry,
        unmatched: list[IconSlot],
    ) -> dict[str, IconOutput]:
        """Generate an SVG for every unmatched slot; return their outputs.

        One batch LLM call authors all the icon names + Recraft prompts,
        then each slot is generated into the run dir. The generated icon
        still belongs to ``chosen`` (it's drawn to fit that set's style),
        so its ``icon_set`` is the chosen set id and ``icon_name`` is the
        AI-authored short name. A slot whose generation fails is dropped
        (logged), never aborting the rest. Returns ``{}`` when there's
        nothing to generate (no LLM call made).
        """
        if not unmatched:
            return {}
        authored = await self._author_prompts(run_ctx, unmatched)

        generated: dict[str, IconOutput] = {}
        for slot in unmatched:
            dest = Path(str(run_ctx.icon_path(slot.id)))
            spec = authored[slot.id]
            try:
                await self._generator.generate(
                    spec.prompt, dest, model=RECRAFT_MODEL
                )
            except Exception as exc:  # noqa: BLE001 — fail soft per slot
                logger.warning(
                    "icon slot %s failed to generate (%s); dropping it",
                    slot.id,
                    exc,
                )
                continue
            generated[slot.id] = IconOutput(
                path=run_ctx.icon_path(slot.id),
                icon_set=chosen.id,
                icon_name=spec.name,
                icon_key=slot.id,
                prompt=spec.prompt,
            )
        return generated

    async def _author_prompts(
        self,
        run_ctx: RunContext,
        unmatched: list[IconSlot],
        *,
        model: str = ICON_PROMPT_MODEL,
    ) -> dict[str, LLMIconPrompt]:
        """One batch LLM call authoring an icon name + Recraft prompt per
        unmatched slot.

        Builds the instruction (rule + brand brief + the unmatched-slot
        inventory, substituted into the prompt-authoring ``.md`` template —
        whose rule bakes in the monochrome / ``currentColor`` / single-
        weight SVG guidance), runs the one structured call, and returns
        ``{slot_id: LLMIconPrompt}`` (each carrying ``name`` + ``prompt``).
        The run's steering (``run_ctx.overwrite_specs``) surfaces as a note."""
        slot_ids = [slot.id for slot in unmatched]
        template = ICON_PROMPT_RULE_PATH.read_text(encoding="utf-8")
        design = run_ctx.cust.design_direction
        lines = [f"- {slot.id}: {slot.description}" for slot in unmatched]
        note = run_ctx.overwrite_specs.prompt_note()
        if note:
            lines.append(f"\n{note}")
        inventory = "\n".join(lines)
        instruction = Template(template).safe_substitute(
            name=design.name,
            short=design.short_desc,
            long=design.long_desc,
            slots=inventory,
        )
        resolved = await self._llm.complete_structured(
            [{"role": "user", "content": instruction}],
            schema=build_icon_prompt_model(slot_ids),
            model=model,
        )
        return {sid: getattr(resolved, sid) for sid in slot_ids}
