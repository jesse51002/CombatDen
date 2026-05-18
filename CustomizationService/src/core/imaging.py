"""Deterministic local image post-processing (no model, no network)."""

from __future__ import annotations

import logging
import shutil
from pathlib import Path

from PIL import Image

logger = logging.getLogger(__name__)

# Alpha at or below this counts as "transparent" (tolerates the faint
# anti-alias fringe a remover leaves behind).
TRANSPARENT_ALPHA_MAX = 16


def transparent_fraction(src: Path) -> float:
    """Fraction of pixels that are (near-)fully transparent.

    A model-free read of "was the backdrop actually removed". A vision
    model receives the PNG flattened to RGB and cannot perceive the alpha
    channel at all, so this question is answered here in pixels, never by
    the model.
    """
    img = Image.open(src).convert("RGBA")
    counts = img.getchannel("A").histogram()  # value -> pixel count
    transparent = sum(counts[: TRANSPARENT_ALPHA_MAX + 1])
    total = img.width * img.height
    return transparent / total if total else 0.0


def autocrop(src: Path, dst: Path) -> None:
    """Crop tight to the subject's alpha bounding box.

    A fully transparent image is copied through to ``dst`` unchanged.
    """
    dst.parent.mkdir(parents=True, exist_ok=True)

    img = Image.open(src).convert("RGBA")
    bbox = img.getbbox()
    if bbox is None:
        logger.warning("no content to crop in %s; copying unchanged", src)
        shutil.copyfile(src, dst)
        return

    img.crop(bbox).save(dst)
