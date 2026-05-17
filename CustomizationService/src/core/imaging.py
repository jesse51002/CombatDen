"""Deterministic local image post-processing (no model, no network)."""

from __future__ import annotations

import logging
import shutil
from pathlib import Path

from PIL import Image

logger = logging.getLogger(__name__)


def autocrop_symmetric(src: Path, dst: Path) -> None:
    """Crop to the subject, keeping the original centre centred.

    A fully transparent image is copied through to ``dst`` unchanged.
    """
    dst.parent.mkdir(parents=True, exist_ok=True)

    img = Image.open(src).convert("RGBA")
    bbox = img.getbbox()
    if bbox is None:
        logger.warning("no content to crop in %s; copying unchanged", src)
        shutil.copyfile(src, dst)
        return

    width, height = img.size
    left, top, right, bottom = bbox
    crop_x = min(left, width - right)
    crop_y = min(top, height - bottom)
    crop_box = (crop_x, crop_y, width - crop_x, height - crop_y)
    img.crop(crop_box).save(dst)
