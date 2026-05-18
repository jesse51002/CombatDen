"""BackgroundService — remove the solid backdrop, then crop.

Extracted from ``ImageGenService`` (which was doing too much). The plain
flat-background prompt makes PhotoRoom reliable enough that there is no
per-image cutout-quality check — the first cutout it produces is accepted;
only a remover transport error is retried, and only a never-produced
cutout falls back to the un-removed raw. The 1% that slips is left to a
later post-agentic loop, not paid for on every image. Atomic per image;
the image module composes it.
"""

from __future__ import annotations

import logging
import shutil
from pathlib import Path

from src.core.errors import ProviderError
from src.core.imaging import gridtrim_autocrop
from src.core.run_context import RunContext
from src.modules.base import CustomizationService
from src.shared.interfaces.background_remover import BackgroundRemover

logger = logging.getLogger(__name__)

CUTOUT_SUFFIX = ".cutout.png"
# Bounded remover re-calls; on exhaustion the un-removed image is kept.
BG_MAX_ATTEMPTS = 3


class BackgroundService(CustomizationService):
    """The background pass: ``run(raw, dest)`` -> wrote final, was-cutout."""

    def __init__(
        self,
        run_ctx: RunContext,
        *,
        bg_remover: BackgroundRemover,
    ) -> None:
        super().__init__(run_ctx)
        self._bg_remover = bg_remover

    async def run(self, raw: Path, dest: Path) -> bool:
        """Remove → crop; write the final PNG to ``dest``.

        Returns whether a cutout was produced (vs. the un-removed image
        kept as a fallback) — for the caller's logging/provenance.
        """
        cutout, ok = await self._remove_background(raw)
        if ok:
            await self._autocrop(cutout, dest)
        else:
            shutil.copyfile(raw, dest)
        return ok

    async def _remove_background(self, raw: Path) -> tuple[Path, bool]:
        """Bounded background removal, no quality check.

        - the first cutout PhotoRoom produces is accepted as-is;
        - only a remover transport error (``ProviderError``) is retried,
          up to ``BG_MAX_ATTEMPTS``;
        - ``(raw, False)`` only if the remover never produced any cutout
          (every attempt raised) — keep the un-removed image.
        """
        cutout = self._run_ctx.image_dir / f"{raw.stem}{CUTOUT_SUFFIX}"
        for attempt in range(BG_MAX_ATTEMPTS):
            try:
                await self._bg_remover.remove(raw, cutout)
            except ProviderError:
                logger.warning(
                    "background remover failed on attempt %d/%d for %s",
                    attempt + 1,
                    BG_MAX_ATTEMPTS,
                    raw.name,
                )
                continue
            return (cutout, True)
        logger.warning(
            "background remover never produced a cutout for %s; "
            "keeping un-removed image",
            raw.name,
        )
        return (raw, False)

    async def _autocrop(self, src: Path, dst: Path) -> None:
        """Crop the cutout tight, grid-trim the halo border, re-crop tight."""
        gridtrim_autocrop(src, dst)
