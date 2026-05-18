"""Deterministic local image post-processing (no model, no network).

Two crops ship here. ``autocrop`` is the tight alpha bounding box —
``PIL.Image.getbbox()`` keeps any pixel with alpha > 0, so the faint
low-alpha halo a background remover leaves behind holds that box loose.
``gridtrim_autocrop`` runs a second pass on top: it walks the
bbox-cropped image as a grid of cells, marks the cells that are pure halo
(a boolean "red" grid — no pixel is ever modified), crops the rectangle
inward past the contiguous fully-red border strips, then re-runs the
alpha bbox so the final box is tight to the real subject instead of the
halo.

It is a *rectangular* crop: interior red cells (a faint hole surrounded
by subject) are kept, since a raster crop cannot carve them out. It also
has a resolution limit — a halo strip thinner than one cell shares its
border cell with real subject, so that cell is not flagged and the thin
strip survives (``getbbox()`` then still includes it). Shrink
``GRID_CELL_PX`` to resolve finer halos at the cost of more per-cell
scans.
"""

from __future__ import annotations

import logging
import shutil
from pathlib import Path

from PIL import Image

logger = logging.getLogger(__name__)

# Alpha at or below this counts as "transparent" (tolerates the faint
# anti-alias fringe a remover leaves behind).
TRANSPARENT_ALPHA_MAX = 16

# Side of each square grid cell, in pixels — the primary tuning knob for
# the second (grid) crop pass. Smaller resolves thinner halos and crops
# closer to the subject but means many more per-cell histogram scans;
# larger is faster but leaves up to ~one cell of slack near the subject
# and cannot catch a halo thinner than a cell.
GRID_CELL_PX = 32

# A grid cell is "red" (halo, trim it) only if BOTH hold (logical AND):
#   1. at least this fraction of its pixels are effectively transparent
#      (alpha <= TRANSPARENT_ALPHA_MAX), AND
RED_CELL_TRANSPARENT_FRACTION = 0.90
#   2. the mean alpha over its *carrying* pixels (alpha above the
#      transparent threshold) is at most this, on the 0-255 scale
#      (~5% of 255 = 12.75).
RED_CELL_MEAN_ALPHA_MAX = 12.75


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


def _alpha_bbox_crop(img: Image.Image) -> Image.Image | None:
    """Crop ``img`` to its alpha bounding box.

    ``None`` when there is no content at all (fully transparent) — the
    caller decides whether to copy the source through unchanged.
    """
    bbox = img.getbbox()
    if bbox is None:
        return None
    return img.crop(bbox)


def autocrop(src: Path, dst: Path) -> None:
    """Crop tight to the subject's alpha bounding box.

    A fully transparent image is copied through to ``dst`` unchanged.
    """
    dst.parent.mkdir(parents=True, exist_ok=True)

    img = Image.open(src).convert("RGBA")
    cropped = _alpha_bbox_crop(img)
    if cropped is None:
        logger.warning("no content to crop in %s; copying unchanged", src)
        shutil.copyfile(src, dst)
        return

    cropped.save(dst)


def _cell_boxes(
    width: int, height: int
) -> tuple[list[tuple[int, int, int, int]], int, int]:
    """Row-major ``(left, upper, right, lower)`` boxes tiling the image as
    ``GRID_CELL_PX`` squares, plus ``(cols, rows)``.

    Edge cells are clamped to the image, so the dimensions need not divide
    evenly. Cell ``(r, c)`` is ``boxes[r * cols + c]``.
    """
    cols = (width + GRID_CELL_PX - 1) // GRID_CELL_PX
    rows = (height + GRID_CELL_PX - 1) // GRID_CELL_PX
    boxes: list[tuple[int, int, int, int]] = []
    for r in range(rows):
        upper = r * GRID_CELL_PX
        lower = min(upper + GRID_CELL_PX, height)
        for c in range(cols):
            left = c * GRID_CELL_PX
            right = min(left + GRID_CELL_PX, width)
            boxes.append((left, upper, right, lower))
    return boxes, cols, rows


def _cell_is_red(img: Image.Image, box: tuple[int, int, int, int]) -> bool:
    """Is this cell pure halo (trim it) rather than real subject?

    Red only if BOTH: at least ``RED_CELL_TRANSPARENT_FRACTION`` of the
    cell is effectively transparent, AND the mean alpha over the pixels
    that *do* carry alpha is at most ``RED_CELL_MEAN_ALPHA_MAX``. If only
    one holds the cell still carries subject and is kept.
    """
    left, upper, right, lower = box
    total = (right - left) * (lower - upper)
    if total == 0:
        return False

    counts = img.crop(box).getchannel("A").histogram()
    transparent = sum(counts[: TRANSPARENT_ALPHA_MAX + 1])
    if transparent / total < RED_CELL_TRANSPARENT_FRACTION:
        return False

    carrying = total - transparent
    if carrying == 0:
        # No carrying pixels at all: fully transparent. Both clauses hold
        # in the limit — unambiguously red, and nothing to average.
        return True
    carrying_alpha = sum(
        v * counts[v] for v in range(TRANSPARENT_ALPHA_MAX + 1, 256)
    )
    return carrying_alpha / carrying <= RED_CELL_MEAN_ALPHA_MAX


def _squeeze_red_borders(
    red: list[list[bool]], cols: int, rows: int
) -> tuple[int, int, int, int] | None:
    """Innermost half-open cell rectangle ``(col0, row0, col1, row1)``
    whose four border rows/cols each hold >=1 non-red cell.

    A rectangular crop can only drop contiguous fully-red border strips;
    interior red cells are kept. Trim top/bottom first, then left/right
    (column scans bounded by the already-trimmed row range, so the result
    is deterministic). ``None`` when every cell is red (nothing survives).
    """
    row0, row1 = 0, rows
    col0, col1 = 0, cols

    def row_all_red(r: int) -> bool:
        return all(red[r][c] for c in range(col0, col1))

    def col_all_red(c: int) -> bool:
        return all(red[r][c] for r in range(row0, row1))

    while row0 < row1 and row_all_red(row0):
        row0 += 1
    while row1 > row0 and row_all_red(row1 - 1):
        row1 -= 1
    while col0 < col1 and col_all_red(col0):
        col0 += 1
    while col1 > col0 and col_all_red(col1 - 1):
        col1 -= 1

    if row0 >= row1 or col0 >= col1:
        return None
    return (col0, row0, col1, row1)


def gridtrim_autocrop(src: Path, dst: Path) -> None:
    """Alpha-bbox crop, then trim pure-halo border strips on a grid, then
    a final alpha-bbox crop.

    The grid trim removes the faint low-alpha halo that ``getbbox()``
    alone keeps, so the re-run bbox lands tight on the real subject. A
    fully transparent image, or one where every cell is halo, is copied
    through / left at the alpha-bbox crop — never a zero-size image.
    """
    dst.parent.mkdir(parents=True, exist_ok=True)

    img = Image.open(src).convert("RGBA")
    bboxed = _alpha_bbox_crop(img)
    if bboxed is None:
        logger.warning("no content to crop in %s; copying unchanged", src)
        shutil.copyfile(src, dst)
        return

    boxes, cols, rows = _cell_boxes(bboxed.width, bboxed.height)
    red = [[False] * cols for _ in range(rows)]
    for idx, box in enumerate(boxes):
        r, c = divmod(idx, cols)
        red[r][c] = _cell_is_red(bboxed, box)

    surviving = _squeeze_red_borders(red, cols, rows)
    if surviving is None:
        logger.warning(
            "grid trim found no subject cells in %s; keeping alpha-bbox crop",
            src,
        )
        bboxed.save(dst)
        return

    col0, row0, col1, row1 = surviving
    top_left = boxes[row0 * cols + col0]
    bottom_right = boxes[(row1 - 1) * cols + (col1 - 1)]
    # Pixel coords come from the surviving cells' own boxes (clamped),
    # never col*GRID_CELL_PX — so a partial edge cell keeps its true extent.
    grid_cropped = bboxed.crop(
        (top_left[0], top_left[1], bottom_right[2], bottom_right[3])
    )

    final = _alpha_bbox_crop(grid_cropped)
    if final is None:
        # Defensive: a surviving (non-red) cell has carrying pixels, so
        # this should not occur — never emit a zero-size image.
        bboxed.save(dst)
        return
    final.save(dst)
