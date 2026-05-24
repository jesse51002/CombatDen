"""RunContext — the validated inputs plus the resolved paths for one run."""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from pathlib import Path

from schema import AbsolutePath, AppFormat, Customization

logger = logging.getLogger(__name__)

RUN_ID_FORMAT = "%Y%m%dT%H%M%SZ"
# Dev/intermediate artifacts (raw generations, cutouts) live here…
IMAGES_DIRNAME = "images"
# …and only the final, delivered per-slot image lands here.
FINAL_IMAGES_DIRNAME = "final_images"
# Per-slot delivered SVG icons (matched from a set or generated) land here.
ICONS_DIRNAME = "icons"
OUTPUT_FILENAME = "output.yaml"


class RunContext:
    """The validated inputs plus the resolved paths for one run."""

    app: AppFormat
    cust: Customization
    app_id: str
    run_id: str
    run_dir: Path
    image_dir: Path
    final_image_dir: Path
    icon_dir: Path

    def __init__(
        self,
        app: AppFormat,
        cust: Customization,
        out_root: Path,
    ) -> None:
        """Store the models and create this run's directory + image folder.

        The run id is a UTC timestamp, so runs sort chronologically; the
        run folder is ``<out_root>/<app_id>/<run_id>``.
        """
        self.app = app
        self.cust = cust
        self.app_id = app.id
        self.run_id = datetime.now(timezone.utc).strftime(RUN_ID_FORMAT)
        self.run_dir = out_root / self.app_id / self.run_id
        self.image_dir = self.run_dir / IMAGES_DIRNAME
        self.final_image_dir = self.run_dir / FINAL_IMAGES_DIRNAME
        self.icon_dir = self.run_dir / ICONS_DIRNAME
        self.run_dir.mkdir(parents=True, exist_ok=True)
        self.image_dir.mkdir(parents=True, exist_ok=True)
        self.final_image_dir.mkdir(parents=True, exist_ok=True)
        self.icon_dir.mkdir(parents=True, exist_ok=True)
        logger.debug("run dir: %s", self.run_dir)

    def image_path(self, slot_id: str) -> AbsolutePath:
        """Absolute path of one slot's *final* delivered PNG.

        Lives in ``final_images/`` so the deliverable is unambiguous; the
        raw generation and cutout stay in ``image_dir`` (``images/``).
        """
        return AbsolutePath(
            str((self.final_image_dir / f"{slot_id}.png").resolve())
        )

    def icon_path(self, slot_id: str) -> AbsolutePath:
        """Absolute path of one slot's delivered SVG icon.

        Lives in ``icons/``; one file per slot, whether the icon was
        matched from a curated set (copied here) or generated (written
        here). Icons have no raw/final split — a single output per slot.
        """
        return AbsolutePath(
            str((self.icon_dir / f"{slot_id}.svg").resolve())
        )

    def output_path(self) -> Path:
        """Path to this run's ``output.yaml``."""
        return self.run_dir / OUTPUT_FILENAME
