"""ImageEditService — authors the instruction for an image-to-image edit.

Image-to-image describes ONLY the change to make to an existing image, not
the whole desired scene — so it cannot reuse the create-new prompt builder
(``image_prompt_rule.md``, full desired-state). This service owns the
separate edit prompt (``image_edit_rule.md``): one structured LLM call that
turns the user's requested change (``OverwriteSpecs.specs``) into a precise,
minimal edit instruction, grounded in the brand brief + palette so a colour
reference resolves to a real palette value.

It returns the bare instruction string; the node hands it to
``ImageGenerator.edit`` along with the current image as the source.
"""

from __future__ import annotations

from pathlib import Path
from string import Template

from schema import ColorPalette
from schema.slots import ImageSlot
from src.core.run_context import RunContext
from src.modules.images.image_models import ImagePrompt
from src.shared.interfaces.llm_client import LLMClient

IMAGE_EDIT_PROMPT_PATH = (
    Path(__file__).parent / "prompts" / "image_edit_rule.md"
)

# The edit-instruction authoring call. A per-call constant, not config:
# turning a requested change + context into a clean edit instruction is a
# small task, so Haiku is plenty.
IMAGE_EDIT_MODEL = "anthropic/claude-haiku-4-5"


class ImageEditService:
    """Builds the prompt and runs the one call that authors an edit
    instruction (the change only) for an image-to-image regeneration."""

    def __init__(self, llm: LLMClient) -> None:
        self._llm = llm

    async def author(
        self,
        run_ctx: RunContext,
        *,
        slot: ImageSlot,
        palette: ColorPalette,
        change: str,
        model: str = IMAGE_EDIT_MODEL,
    ) -> str:
        """Author the edit instruction for ``slot`` from the requested
        ``change``, grounded in the brand brief + palette. Returns the bare
        instruction string (the change only)."""
        template = IMAGE_EDIT_PROMPT_PATH.read_text(encoding="utf-8")
        design = run_ctx.cust.design_direction
        palette_summary = "\n".join(
            f"  {slot_id}: {color.color.oklch!s} — {color.display_name}"
            for slot_id, color in palette.colors.items()
        )
        prompt = Template(template).safe_substitute(
            name=design.name,
            short=design.short_desc,
            palette=palette_summary,
            subject=slot.description,
            change=change,
        )
        result = await self._llm.complete_structured(
            [{"role": "user", "content": prompt}],
            schema=ImagePrompt,
            model=model,
        )
        return result.prompt
