"""ImageGenService — the image module: resolve image slots one at a time."""

from __future__ import annotations

import base64
import logging
import shutil
from pathlib import Path
from string import Template
from typing import Any

from schema import ImageOutput, ImageSlot
from src.core.config import settings
from src.core.errors import ProviderError
from src.core.imaging import autocrop_symmetric
from src.core.run_context import RunContext
from src.modules.base import CustomizationService
from src.modules.colors.color_models import ColorPalette
from src.modules.images.image_models import BackgroundCheck, ImagePrompt
from src.shared.interfaces.background_remover import BackgroundRemover
from src.shared.interfaces.image_generator import ImageGenerator
from src.shared.interfaces.llm_client import LLMClient

logger = logging.getLogger(__name__)

IMAGE_PROMPT_PATH = Path(__file__).parent / "prompts" / "image_prompt_rule.md"
BG_CHECK_PROMPT_PATH = Path(__file__).parent / "prompts" / "background_check.md"
RAW_SUFFIX = ".raw.png"
CUTOUT_SUFFIX = ".cutout.png"
PNG_DATA_URL_PREFIX = "data:image/png;base64,"


class ImageGenService(CustomizationService):
    """The image module, atomic per image: ``run(slot, palette) ->
    ImageOutput``. The executor owns the per-slot loop."""

    def __init__(
        self,
        run_ctx: RunContext,
        *,
        llm: LLMClient,
        image_gen: ImageGenerator,
        bg_remover: BackgroundRemover,
    ) -> None:
        super().__init__(run_ctx)
        self._llm = llm
        self._image_gen = image_gen
        self._bg_remover = bg_remover

    async def run(
        self, slot: ImageSlot, palette: ColorPalette
    ) -> ImageOutput:
        """Resolve one slot end to end: prompt → generate → cutout → crop."""
        prompt = await self._build_prompt(slot, palette)
        raw = await self._generate(slot, prompt)
        cutout, ok = await self._remove_background(raw)
        final = Path(str(self._run_ctx.image_path(slot.id)))
        if ok:
            await self._autocrop(cutout, final)
        else:
            shutil.copyfile(raw, final)
        return ImageOutput(path=self._run_ctx.image_path(slot.id), prompt=prompt)

    async def _build_prompt(self, slot: ImageSlot, palette: Any) -> str:
        """Brief + slot + palette → image prompt (rationale just sharpens it)."""
        template = IMAGE_PROMPT_PATH.read_text(encoding="utf-8")
        design = self._run_ctx.cust.design_direction
        palette_summary = "\n".join(
            f"  {slot_id}: {color.hex} ({color.vibe})"
            for slot_id, color in palette.colors.items()
        )
        prompt = Template(template).safe_substitute(
            name=design.name,
            short=design.short_desc,
            long=design.long_desc,
            palette=palette_summary,
            subject=slot.description,
        )
        result = await self._llm.complete_structured(
            [{"role": "user", "content": prompt}], schema=ImagePrompt
        )
        return result.prompt

    async def _generate(self, slot: ImageSlot, prompt: str) -> Path:
        """Generate the raw image (subject on a plain solid background)."""
        dest = self._run_ctx.image_dir / f"{slot.id}{RAW_SUFFIX}"
        await self._image_gen.generate(prompt, dest)
        return dest

    async def _remove_background(self, raw: Path) -> tuple[Path, bool]:
        """Bounded background removal, validated each attempt.

        Returns ``(cutout, True)`` on success, or ``(raw, False)`` if every
        attempt failed and the un-removed image is kept.
        """
        cutout = self._run_ctx.image_dir / f"{raw.stem}{CUTOUT_SUFFIX}"
        for attempt in range(settings.bg_max_attempts):
            try:
                await self._bg_remover.remove(raw, cutout)
            except ProviderError:
                logger.warning(
                    "background remover failed on attempt %d/%d for %s",
                    attempt + 1,
                    settings.bg_max_attempts,
                    raw.name,
                )
                continue
            verdict = await self._validate_background(raw, cutout)
            if verdict.ok:
                return (cutout, True)
            logger.warning(
                "background cutout rejected on attempt %d/%d for %s: %s",
                attempt + 1,
                settings.bg_max_attempts,
                raw.name,
                verdict.reason,
            )
        logger.warning(
            "background removal exhausted for %s; keeping un-removed image",
            raw.name,
        )
        return (raw, False)

    async def _validate_background(
        self, original: Path, removed: Path
    ) -> BackgroundCheck:
        """Ask the Gemini-vision validator whether the cutout is clean."""
        instruction = BG_CHECK_PROMPT_PATH.read_text(encoding="utf-8")
        encoded = base64.b64encode(removed.read_bytes()).decode("ascii")
        data_url = f"{PNG_DATA_URL_PREFIX}{encoded}"
        messages = [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": instruction},
                    {"type": "image_url", "image_url": {"url": data_url}},
                ],
            }
        ]
        return await self._llm.complete_structured(
            messages,
            schema=BackgroundCheck,
            model=settings.bg_validation_model,
        )

    async def _autocrop(self, src: Path, dst: Path) -> None:
        """Symmetrically crop the clean cutout to its subject."""
        autocrop_symmetric(src, dst)
