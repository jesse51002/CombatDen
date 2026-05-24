"""LottieSelectionService — CALL 1: pick ONE preset for a lottie slot.

Brand/intent reasoning only: the LLM is shown the brand brief, the slot
description, and the candidate presets (already filtered to the slot's
required type), and returns one ``preset_id``. For a reveal slot the
revealed image's prompt is included so the pick can fit what it reveals.

No palette here — the colour-saturated region->role mapping is a separate
call (``LottieRecolorService``) so each prompt stays focused.
"""

from __future__ import annotations

from pathlib import Path
from string import Template

from schema.lottie_library import LottiePreset
from schema.lottie_type import LottieType
from schema.output.image_output import ImageOutput
from schema.slots import LottieSlot
from src.core.errors import ProviderError
from src.core.run_context import RunContext
from src.modules.lotties.lottie_models import build_selection_model
from src.shared.interfaces.llm_client import LLMClient

SELECTION_PROMPT_PATH = (
    Path(__file__).parent / "prompts" / "lottie_selection_rule.md"
)
# Injected ONLY for reveal slots: the revealed image's description, so the
# common standalone prompt carries no reveal wording at all.
REVEALED_BLOCK_TMPL = (
    "\nThis animation plays in the background while an image is revealed. "
    "The revealed image is described as:\n  $revealed\n"
    "Pick an animation whose energy and motion suit revealing that image."
)

# Per-call constant, not config: the model is a property of this call.
# Haiku is plenty — the closed schema + candidate-membership contract do
# the constraining; this is a bounded pick from a short list.
LOTTIE_SELECTION_MODEL = "anthropic/claude-haiku-4-5"


class LottieSelectionService:
    """Runs the one structured selection call and returns the picked
    preset (looked up from the offered candidates, so the chosen id can't
    be anything the library doesn't have)."""

    def __init__(self, llm: LLMClient) -> None:
        self._llm = llm

    async def resolve(
        self,
        run_ctx: RunContext,
        *,
        slot: LottieSlot,
        candidates: list[LottiePreset],
        revealed: ImageOutput | None,
        model: str = LOTTIE_SELECTION_MODEL,
    ) -> LottiePreset:
        """Pick one preset for ``slot`` from ``candidates``."""
        if not candidates:
            raise ProviderError(
                f"no lottie preset in the library carries the required "
                f"type {slot.required_type.value!r} for slot {slot.id!r}"
            )
        by_id = {preset.id: preset for preset in candidates}
        response_model = build_selection_model(
            candidate_ids=list(by_id)
        )
        prompt = self._build_prompt(run_ctx, slot, candidates, revealed)
        pick = await self._llm.complete_structured(
            [{"role": "user", "content": prompt}],
            schema=response_model,
            model=model,
        )
        # The validator already enforced membership, so this is a hit.
        return by_id[pick.preset_id]

    @staticmethod
    def _build_prompt(
        run_ctx: RunContext,
        slot: LottieSlot,
        candidates: list[LottiePreset],
        revealed: ImageOutput | None,
    ) -> str:
        """Rule + brand brief + slot + candidate listing (+ reveal block)."""
        template = SELECTION_PROMPT_PATH.read_text(encoding="utf-8")
        design = run_ctx.cust.design_direction
        listing = "\n".join(
            f"  {preset.id}: {preset.display_name} — {preset.description}"
            for preset in candidates
        )
        if revealed is not None:
            revealed_block = Template(REVEALED_BLOCK_TMPL).safe_substitute(
                revealed=revealed.prompt
            )
        else:
            revealed_block = ""
        return Template(template).safe_substitute(
            name=design.name,
            short=design.short_desc,
            long=design.long_desc,
            slot=slot.description,
            candidates=listing,
            revealed_block=revealed_block,
        )
