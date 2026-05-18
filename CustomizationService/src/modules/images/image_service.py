"""ImageGenService — the image module: resolve image slots one at a time.

Orchestrates one image: write the prompt, classify its complexity (which
picks the generator's quality tier), generate, then hand off to the
``BackgroundService`` for removal/validation/crop. The executor owns the
per-slot loop; this stays atomic per image.
"""

from __future__ import annotations

import logging
from pathlib import Path
from string import Template
from typing import Any

from schema import Complexity, ImageOutput, ImageSlot
from src.core.errors import ProviderError
from src.core.run_context import RunContext
from src.modules.base import CustomizationService
from src.modules.colors.color_models import ColorPalette
from src.modules.images.background_service import BackgroundService
from src.modules.images.complexity_service import ComplexityClassifier
from src.modules.images.image_models import ImagePrompt
from src.modules.images.style_service import StyleAdherenceService
from src.shared.interfaces.image_generator import ImageGenerator
from src.shared.interfaces.llm_client import LLMClient

logger = logging.getLogger(__name__)

IMAGE_PROMPT_PATH = Path(__file__).parent / "prompts" / "image_prompt_rule.md"
RAW_SUFFIX = ".raw.png"
# The asset composites onto the app's own base surface, so the generated
# background is fixed to that surface by theme: a matching flat field makes
# the cutout trivial. Named literally — image models render these reliably.
THEME_BG_DARK = "pure black (the app is in dark mode)"
THEME_BG_LIGHT = "pure white (the app is in light mode)"

# Per-call constants, not config — this flow is now too specific for
# global config. Override in dev (bake-off scripts under `scripts/`);
# production uses these. ``IMAGE_GEN_MODEL`` is provider-prefixed and the
# generic litellm image generator routes on it (swap providers here).
IMAGE_PROMPT_MODEL = "anthropic/claude-opus-4-7"
IMAGE_GEN_MODEL = "openai/gpt-image-2"
# Regular nano-banana, via litellm's image-edit path. Per-call constant
# (one-line swap), same as the other model ids here. Used once, only when
# the style check fails — never looped.
STYLE_EDIT_MODEL = "gemini/gemini-2.5-flash-image-preview"
# Bounded re-calls: image-provider moderation/infra is non-deterministic,
# so a benign prompt can blip on one call and pass the next. There is no
# usable fallback for a missing image, so exhaustion fails the run.
IMAGE_GEN_MAX_ATTEMPTS = 3
# Complexity tier → generator quality. ``high`` is reserved/unused for now
# (overkill); flip it to "high" here to enable it — no schema change.
QUALITY_BY_COMPLEXITY: dict[Complexity, str] = {
    Complexity.LOW: "low",
    Complexity.MEDIUM: "medium",
    Complexity.HIGH: "medium",
}


class ImageGenService(CustomizationService):
    """The image module, atomic per image: ``run(slot, palette) ->
    ImageOutput``. The executor owns the per-slot loop."""

    def __init__(
        self,
        run_ctx: RunContext,
        *,
        llm: LLMClient,
        image_gen: ImageGenerator,
        classifier: ComplexityClassifier,
        style: StyleAdherenceService,
        background: BackgroundService,
    ) -> None:
        super().__init__(run_ctx)
        self._llm = llm
        self._image_gen = image_gen
        self._classifier = classifier
        self._style = style
        self._background = background

    async def run(
        self,
        slot: ImageSlot,
        palette: ColorPalette,
        *,
        prompt_model: str = IMAGE_PROMPT_MODEL,
    ) -> ImageOutput:
        """Resolve one slot end to end: prompt → classify → generate →
        style check → (one-time edit) → cutout → crop.

        ``prompt_model`` drives the prompt-generation call (override in dev
        to compare models). Complexity classification picks the generator's
        quality tier. The style check judges whether the raw image realises
        the prompt; on a miss exactly one corrective edit is applied (no
        loop, no re-check) before the background pass — delegated to
        ``BackgroundService`` — runs on the resulting image."""
        prompt = await self._build_prompt(slot, palette, model=prompt_model)
        complexity = await self._classifier.classify(prompt)
        quality = QUALITY_BY_COMPLEXITY[complexity]
        raw = await self._generate(slot, prompt, quality)
        final = Path(str(self._run_ctx.image_path(slot.id)))

        verdict = await self._style.check(raw, prompt)
        edited_prompt: str | None = None
        edited_reason: str | None = None
        if not verdict.adherent:
            # One corrective pass only: if a single targeted edit toward
            # the prompt's style does not land, more won't — so we ship
            # the edited image as-is, no re-check.
            edited = raw.with_name(f"{raw.stem}.edited.png")
            await self._image_gen.edit(
                raw,
                verdict.edit_instruction,
                edited,
                model=STYLE_EDIT_MODEL,
            )
            raw = edited
            edited_prompt = verdict.edit_instruction
            edited_reason = verdict.reason

        await self._background.run(raw, final)
        return ImageOutput(
            path=self._run_ctx.image_path(slot.id),
            prompt=prompt,
            complexity=complexity,
            adherent=verdict.adherent,
            edited_prompt=edited_prompt,
            edited_reason=edited_reason,
        )

    async def _build_prompt(
        self,
        slot: ImageSlot,
        palette: Any,
        *,
        model: str = IMAGE_PROMPT_MODEL,
    ) -> str:
        """Brief + slot + palette → image prompt."""
        template = IMAGE_PROMPT_PATH.read_text(encoding="utf-8")
        design = self._run_ctx.cust.design_direction
        dark_mode = self._run_ctx.cust.colors_direction.dark_mode
        palette_summary = "\n".join(
            f"  {slot_id}: {color.oklch} — {color.display_name}: "
            f"{color.description}"
            for slot_id, color in palette.colors.items()
        )
        prompt = Template(template).safe_substitute(
            name=design.name,
            short=design.short_desc,
            long=design.long_desc,
            palette=palette_summary,
            theme_background=(
                THEME_BG_DARK if dark_mode else THEME_BG_LIGHT
            ),
            subject=slot.description,
        )
        result = await self._llm.complete_structured(
            [{"role": "user", "content": prompt}],
            schema=ImagePrompt,
            model=model,
        )
        return result.prompt

    async def _generate(
        self, slot: ImageSlot, prompt: str, quality: str
    ) -> Path:
        """Generate the raw image (subject on a plain solid background).

        The image provider's moderation/infra is non-deterministic — a
        benign prompt can hit a false-positive block, a transient failure,
        or a timeout on one call and succeed on the next — so generation is
        retried a bounded number of times. Unlike background removal there
        is no usable fallback for a missing image, so exhaustion re-raises
        the last provider error and fails the run.
        """
        dest = self._run_ctx.image_dir / f"{slot.id}{RAW_SUFFIX}"
        last_error: ProviderError | None = None
        for attempt in range(IMAGE_GEN_MAX_ATTEMPTS):
            try:
                await self._image_gen.generate(
                    prompt, dest, model=IMAGE_GEN_MODEL, quality=quality
                )
                return dest
            except ProviderError as exc:
                last_error = exc
                logger.warning(
                    "image generation failed on attempt %d/%d for %s: %s",
                    attempt + 1,
                    IMAGE_GEN_MAX_ATTEMPTS,
                    slot.id,
                    exc,
                )
        raise last_error or ProviderError(
            f"image generation produced nothing for {slot.id}"
        )
