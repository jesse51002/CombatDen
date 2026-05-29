"""RunContext — the validated inputs plus the resolved paths for one run."""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from pathlib import Path

from schema import (
    AbsolutePath,
    AppFormat,
    Customization,
    Output,
    OverwriteSpecs,
)

from src.core.errors import PipelineError
from src.core.util import load_yaml

logger = logging.getLogger(__name__)

RUN_ID_FORMAT = "%Y%m%dT%H%M%SZ"
# The output root every run dir lives under (``<root>/<app_id>/<run_id>``).
# A safety rail for the destructive full-run overwrite: the pipeline refuses
# to clear a run dir that does not sit under a directory of this name.
OUTPUT_ROOT_DIRNAME = "apps"
# Dev/intermediate artifacts (raw generations, cutouts) live here…
IMAGES_DIRNAME = "images"
# …and only the final, delivered per-slot image lands here.
FINAL_IMAGES_DIRNAME = "final_images"
# Per-slot delivered SVG icons (matched from a set or generated) land here.
ICONS_DIRNAME = "icons"
OUTPUT_FILENAME = "output.yaml"
# The two input artifacts copied into a run dir as provenance; the in-place
# scripts (expand, regen) read them back as the run's contract.
APP_FILENAME = "app.yaml"
CUSTOMIZATION_FILENAME = "customization.yaml"
# Append-only spend ledger for `expand` passes (see schema ExpansionCostLog).
# Sits beside output.yaml; absent until a run is first expanded.
EXPANSION_COST_FILENAME = "expansion_cost.yaml"


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
    overwrite_specs: OverwriteSpecs

    def __init__(
        self,
        app: AppFormat,
        cust: Customization,
        out_root: Path,
        run_id: str | None = None,
        overwrite_specs: OverwriteSpecs | None = None,
    ) -> None:
        """Store the models and create this run's directory + image folder.

        The run folder is ``<out_root>/<app_id>/<run_id>``. A fresh run
        leaves ``run_id`` unset and gets a UTC timestamp, so runs sort
        chronologically. Passing an existing ``run_id`` instead targets
        that directory in place (the ``mkdir(exist_ok=True)`` calls below
        are then harmless no-ops) — this is how ``expand`` reopens a saved
        run to seed its done nodes and generate only what's missing.

        ``overwrite_specs`` is the run's single steering object (the
        reopen-time ``--spec`` plus any per-module knobs). It lives here so
        nothing has to hand-thread it through the executor → registry → node
        → service chain: every layer already carries the ``RunContext`` and
        reads ``run_ctx.overwrite_specs`` where it needs the steering. A fresh
        full run (no reopen) leaves it as an empty ``OverwriteSpecs()``.
        """
        self.app = app
        self.cust = cust
        self.overwrite_specs = overwrite_specs or OverwriteSpecs()
        self.app_id = app.id
        self.run_id = (
            run_id
            if run_id is not None
            else datetime.now(timezone.utc).strftime(RUN_ID_FORMAT)
        )
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

    def expansion_cost_path(self) -> Path:
        """Path to this run's ``expansion_cost.yaml`` spend ledger."""
        return self.run_dir / EXPANSION_COST_FILENAME


def load_run(
    run_dir: Path, *, app_yaml: Path | None = None
) -> tuple[AppFormat, Customization, Output]:
    """Validate and load an existing run dir's three YAML artifacts.

    The shared entry for the in-place scripts (``expand``, ``regen``)
    that reopen a saved run. Checks the dir holds ``app.yaml``,
    ``customization.yaml`` and ``output.yaml``, and that the app id matches
    the app-level directory name — so the dir really is
    ``<out_root>/<app_id>/<run_id>`` and ``RunContext(run_id=...)`` will
    target it correctly. Raises ``PipelineError`` for a missing dir/file or
    an id mismatch; model validation raises its own ``ValidationError``.

    ``app_yaml`` overrides where the slot inventory is read from: the run
    dir's ``app.yaml`` is a frozen *snapshot* from when the run was made, so
    to expand against an **updated** inventory (a slot added to the live
    ``app.yaml``) the caller passes its path here. ``customization.yaml`` and
    ``output.yaml`` are always the run's own.
    """
    if not run_dir.is_dir():
        raise PipelineError(f"not a directory: {run_dir}")
    for name in (APP_FILENAME, CUSTOMIZATION_FILENAME, OUTPUT_FILENAME):
        if not (run_dir / name).is_file():
            raise PipelineError(f"missing {name} in {run_dir}")
    app_path = app_yaml if app_yaml is not None else run_dir / APP_FILENAME
    if not app_path.is_file():
        raise PipelineError(f"no such app.yaml: {app_path}")

    app = AppFormat.model_validate(load_yaml(app_path))
    cust = Customization.model_validate(
        load_yaml(run_dir / CUSTOMIZATION_FILENAME)
    )
    output = Output.model_validate(load_yaml(run_dir / OUTPUT_FILENAME))

    app_dir_name = run_dir.parent.name
    if app.id != app_dir_name:
        raise PipelineError(
            f"app id {app.id!r} in {APP_FILENAME} does not match the app "
            f"directory name {app_dir_name!r} ({run_dir.parent}); is "
            "--run-dir pointing at <out_root>/<app_id>/<run_id>?"
        )
    return app, cust, output
