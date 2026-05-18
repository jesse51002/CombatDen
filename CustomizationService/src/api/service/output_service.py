"""Filesystem reads behind the API: locate a run's output + its images.

App-agnostic: ``app_id`` / ``run_id`` / ``slot_id`` are opaque,
pattern-checked strings. The absolute ``path`` inside ``output.yaml`` is
deliberately ignored — the pipeline writes it against its own machine and
it is unreliable; the delivered image is resolved by one fixed rule:
``<run_dir>/final_images/<slot_id>.png``. There is no fallback to
``images/`` (that holds raw/cutout intermediates, never the
deliverable) — a missing file is a clear, loud failure, not a dir hunt.
"""

from __future__ import annotations

import re
from pathlib import Path

import yaml
from pydantic import ValidationError

from schema import Output
from src.api.config import settings
from src.api.errors import InvalidRunError, NotFoundError

OUTPUT_FILENAME = "output.yaml"
# The one place a delivered per-slot PNG lives. `images/` (raw + cutout
# intermediates) is never served — by contract, not by guesswork.
FINAL_IMAGES_DIRNAME = "final_images"
IMAGE_SUFFIX = ".png"

# snake_case ids (mirrors schema.output.Output's app/slot rule).
_ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")
# Run ids are UTC stamps like `20260517T052107Z` — alphanumeric only.
_RUN_ID_PATTERN = re.compile(r"^[0-9A-Za-z]+$")


def _safe_run_dir(app_id: str, run_id: str) -> Path:
    """``apps_root/app_id/run_id``, but only if the ids are well-formed and
    the resolved path stays inside ``apps_root`` (path-traversal guard)."""
    if not _ID_PATTERN.match(app_id) or not _RUN_ID_PATTERN.match(run_id):
        raise NotFoundError(f"no run {app_id}/{run_id}")
    apps_root = settings.apps_root.resolve()
    run_dir = (apps_root / app_id / run_id).resolve()
    if apps_root not in run_dir.parents:
        raise NotFoundError(f"no run {app_id}/{run_id}")
    return run_dir


async def load_output(app_id: str, run_id: str) -> Output:
    """The run's validated ``output.yaml``.

    Missing run/file -> ``NotFoundError`` (404). A file that is present
    but unparseable or stale against the current schema ->
    ``InvalidRunError`` (422): the run is real, the artifact just no
    longer conforms — that is not a server fault.
    """
    output_file = _safe_run_dir(app_id, run_id) / OUTPUT_FILENAME
    if not output_file.is_file():
        raise NotFoundError(f"no output for {app_id}/{run_id}")
    try:
        return Output.model_validate(yaml.safe_load(output_file.read_text()))
    except (yaml.YAMLError, ValidationError) as exc:
        raise InvalidRunError(
            f"run {app_id}/{run_id} exists but its {OUTPUT_FILENAME} does "
            "not match the current schema; regenerate it"
        ) from exc


async def resolve_image_file(
    app_id: str, run_id: str, slot_id: str
) -> Path:
    """The on-disk PNG for one declared image slot.

    Exactly ``<run_dir>/final_images/<slot_id>.png`` — no fallback. Every
    failure is a 404 (``NotFoundError``) with a message that says which
    of the three distinct cases it is:

    * ``slot_id`` is malformed,
    * the slot is not declared in the run's ``output.yaml``,
    * the slot is declared but its PNG is absent (an incomplete run).

    (A missing/stale ``output.yaml`` still surfaces as 404/422 from
    :func:`load_output`.)
    """
    if not _ID_PATTERN.match(slot_id):
        raise NotFoundError(f"invalid slot id {slot_id!r}")
    output = await load_output(app_id, run_id)
    if slot_id not in output.images:
        raise NotFoundError(
            f"slot {slot_id!r} is not declared in run {app_id}/{run_id}"
        )
    image = (
        _safe_run_dir(app_id, run_id)
        / FINAL_IMAGES_DIRNAME
        / f"{slot_id}{IMAGE_SUFFIX}"
    )
    if not image.is_file():
        raise NotFoundError(
            f"slot {slot_id!r} is declared but its image is missing from "
            f"{FINAL_IMAGES_DIRNAME}/ — run {app_id}/{run_id} is incomplete"
        )
    return image
