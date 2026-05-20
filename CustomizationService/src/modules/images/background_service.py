"""BackgroundService — remove the solid backdrop, then crop.

A sub-service the image node composes (kept out of the node itself,
which was doing too much). The plain
flat-background prompt makes PhotoRoom reliable enough that there is no
per-image cutout-quality check — the first cutout it produces is accepted;
only a remover transport error is retried, and only a never-produced
cutout falls back to the un-removed raw. The 1% that slips is left to a
later post-agentic loop, not paid for on every image. Atomic per image;
the image module composes it.

Cropping is two passes, both owned here (it is background-removal
post-processing, not generic core).  The alpha bounding box
(``PIL.Image.getbbox()``) keeps any pixel with alpha > 0, so the faint
low-alpha halo the remover leaves behind holds that box loose. The grid
trim runs on top: it walks the bbox-cropped image as a grid of cells,
marks the cells that are pure halo (a boolean "red" grid — no pixel is
ever modified), crops the rectangle inward past the contiguous fully-red
border strips, then re-runs the alpha bbox so the final box is tight to
the real subject instead of the halo. It is a *rectangular* crop:
interior red cells (a faint hole surrounded by subject) are kept, since a
raster crop cannot carve them out. It also has a resolution limit — a
halo strip thinner than one cell shares its border cell with real
subject, so that cell is not flagged and the thin strip survives
(``getbbox()`` then still includes it). Shrink ``GRID_CELL_PX`` to
resolve finer halos at the cost of more per-cell scans.
"""

from __future__ import annotations

import logging
import shutil
from pathlib import Path

from PIL import Image

from src.core.errors import ProviderError
from src.shared.interfaces.background_remover import BackgroundRemover

logger = logging.getLogger(__name__)

CUTOUT_SUFFIX = ".cutout.png"
# A retried removal reuses the canonical cutout dest; before the next
# attempt overwrites a cutout a prior attempt already wrote, that file is
# moved aside under this name so the full attempt lineage survives on disk
# for inspection. ``{n}`` is the 1-based number of the preserved attempt.
# The happy path (no retry) never produces one of these.
CUTOUT_ATTEMPT_TMPL = "{stem}.attempt{n}.png"
# Bounded remover re-calls; on exhaustion the un-removed image is kept.
BG_MAX_ATTEMPTS = 3

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


class BackgroundService:
    """The background pass: ``run(raw, dest)`` -> wrote final, was-cutout."""

    def __init__(self, *, bg_remover: BackgroundRemover) -> None:
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
        # The raw image is always written into the run's image dir, so its
        # own parent is that dir — no run_ctx needed for the cutout path.
        cutout = raw.parent / f"{raw.stem}{CUTOUT_SUFFIX}"
        for attempt in range(BG_MAX_ATTEMPTS):
            # Never clobber a cutout an earlier attempt actually wrote:
            # move it aside under its attempt number before this one
            # overwrites the canonical dest. (A hard-failed attempt raises
            # before writing, so usually there is nothing here to preserve.)
            if attempt and cutout.exists():
                cutout.rename(
                    cutout.with_name(
                        CUTOUT_ATTEMPT_TMPL.format(
                            stem=cutout.stem, n=attempt
                        )
                    )
                )
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
        self._grid_trim_crop(src, dst)

    # --- crop passes (deterministic, no model, no network) -------------

    @staticmethod
    def _alpha_bbox_crop(img: Image.Image) -> Image.Image | None:
        """Crop ``img`` to its alpha bounding box.

        ``None`` when there is no content at all (fully transparent) —
        the caller decides whether to copy the source through unchanged.
        """
        bbox = img.getbbox()
        if bbox is None:
            return None
        return img.crop(bbox)

    @staticmethod
    def _cell_boxes(
        width: int, height: int
    ) -> tuple[list[tuple[int, int, int, int]], int, int]:
        """Row-major ``(left, upper, right, lower)`` boxes tiling the
        image as ``GRID_CELL_PX`` squares, plus ``(cols, rows)``.

        Edge cells are clamped to the image, so the dimensions need not
        divide evenly. Cell ``(r, c)`` is ``boxes[r * cols + c]``.
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

    @staticmethod
    def _cell_is_red(
        img: Image.Image, box: tuple[int, int, int, int]
    ) -> bool:
        """Is this cell pure halo (trim it) rather than real subject?

        Red only if BOTH: at least ``RED_CELL_TRANSPARENT_FRACTION`` of
        the cell is effectively transparent, AND the mean alpha over the
        pixels that *do* carry alpha is at most
        ``RED_CELL_MEAN_ALPHA_MAX``. If only one holds the cell still
        carries subject and is kept.
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
            # No carrying pixels at all: fully transparent. Both clauses
            # hold in the limit — unambiguously red, nothing to average.
            return True
        carrying_alpha = sum(
            v * counts[v] for v in range(TRANSPARENT_ALPHA_MAX + 1, 256)
        )
        return carrying_alpha / carrying <= RED_CELL_MEAN_ALPHA_MAX

    @staticmethod
    def _squeeze_red_borders(
        red: list[list[bool]], cols: int, rows: int
    ) -> tuple[int, int, int, int] | None:
        """Innermost half-open cell rectangle ``(col0, row0, col1, row1)``
        whose four border rows/cols each hold >=1 non-red cell.

        A rectangular crop can only drop contiguous fully-red border
        strips; interior red cells are kept. Trim top/bottom first, then
        left/right (column scans bounded by the already-trimmed row
        range, so the result is deterministic). ``None`` when every cell
        is red (nothing survives).
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

    def _grid_trim_crop(self, src: Path, dst: Path) -> None:
        """Alpha-bbox crop, trim pure-halo border strips on a grid, then
        a final alpha-bbox crop.

        The grid trim removes the faint low-alpha halo that ``getbbox()``
        alone keeps, so the re-run bbox lands tight on the real subject.
        A fully transparent image, or one where every cell is halo, is
        copied through / left at the alpha-bbox crop — never a zero-size
        image.
        """
        dst.parent.mkdir(parents=True, exist_ok=True)

        img = Image.open(src).convert("RGBA")
        bboxed = self._alpha_bbox_crop(img)
        if bboxed is None:
            logger.warning(
                "no content to crop in %s; copying unchanged", src
            )
            shutil.copyfile(src, dst)
            return

        boxes, cols, rows = self._cell_boxes(bboxed.width, bboxed.height)
        red = [[False] * cols for _ in range(rows)]
        for idx, box in enumerate(boxes):
            r, c = divmod(idx, cols)
            red[r][c] = self._cell_is_red(bboxed, box)

        surviving = self._squeeze_red_borders(red, cols, rows)
        if surviving is None:
            logger.warning(
                "grid trim found no subject cells in %s; "
                "keeping alpha-bbox crop",
                src,
            )
            bboxed.save(dst)
            return

        col0, row0, col1, row1 = surviving
        top_left = boxes[row0 * cols + col0]
        bottom_right = boxes[(row1 - 1) * cols + (col1 - 1)]
        # Pixel coords come from the surviving cells' own boxes (clamped),
        # never col*GRID_CELL_PX — a partial edge cell keeps its extent.
        grid_cropped = bboxed.crop(
            (top_left[0], top_left[1], bottom_right[2], bottom_right[3])
        )

        final = self._alpha_bbox_crop(grid_cropped)
        if final is None:
            # Defensive: a surviving (non-red) cell has carrying pixels,
            # so this should not occur — never emit a zero-size image.
            bboxed.save(dst)
            return
        final.save(dst)
