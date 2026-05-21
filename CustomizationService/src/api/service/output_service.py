"""OutputService — filesystem reads behind the API: locate a run's
output + its images.

App-agnostic: ``app_id`` / ``run_id`` / ``slot_id`` are opaque,
pattern-checked strings. The absolute ``path`` inside ``output.yaml``
is deliberately ignored — the pipeline writes it against its own
machine and it is unreliable; the delivered image is resolved by one
fixed rule: ``<run_dir>/final_images/<slot_id>.png``. There is no
fallback to ``images/`` (that holds raw/cutout intermediates, never
the deliverable) — a missing file is a clear, loud failure, not a
dir hunt.

The ``apps_root`` is injected so tests can point the service at the
fixture tree without monkeypatching module-level globals. The API
process holds one process-scoped instance (see
``output_service_instance`` below) reused across every request.
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


class OutputService:
    """Loads a run's ``output.yaml`` and resolves declared per-slot
    image paths on disk.

    Constructor takes the apps root so tests can point at the fixture
    tree without monkeypatching ``settings.apps_root``.
    """

    def __init__(self, apps_root: Path) -> None:
        self._apps_root = apps_root

    async def load(self, app_id: str, run_id: str) -> Output:
        """The run's validated ``output.yaml``.

        Missing run/file -> ``NotFoundError`` (404). A file that is
        present but unparseable or stale against the current schema ->
        ``InvalidRunError`` (422): the run is real, the artifact just
        no longer conforms — that is not a server fault.
        """
        output_file = self._safe_run_dir(app_id, run_id) / OUTPUT_FILENAME
        if not output_file.is_file():
            raise NotFoundError(f"no output for {app_id}/{run_id}")
        try:
            return Output.model_validate(
                yaml.safe_load(output_file.read_text())
            )
        except (yaml.YAMLError, ValidationError) as exc:
            raise InvalidRunError(
                f"run {app_id}/{run_id} exists but its "
                f"{OUTPUT_FILENAME} does not match the current schema; "
                "regenerate it"
            ) from exc

    async def image_file(
        self, app_id: str, run_id: str, slot_id: str
    ) -> Path:
        """The on-disk PNG for one declared image slot.

        Exactly ``<run_dir>/final_images/<slot_id>.png`` — no fallback.
        Every failure is a 404 (``NotFoundError``) with a message that
        says which of the three distinct cases it is:

        * ``slot_id`` is malformed,
        * the slot is not declared in the run's ``output.yaml``,
        * the slot is declared but its PNG is absent (an incomplete
          run).

        (A missing/stale ``output.yaml`` still surfaces as 404/422
        from :meth:`load`.)
        """
        if not _ID_PATTERN.match(slot_id):
            raise NotFoundError(f"invalid slot id {slot_id!r}")
        output = await self.load(app_id, run_id)
        if slot_id not in output.image_set.images:
            raise NotFoundError(
                f"slot {slot_id!r} is not declared in run "
                f"{app_id}/{run_id}"
            )
        image = (
            self._safe_run_dir(app_id, run_id)
            / FINAL_IMAGES_DIRNAME
            / f"{slot_id}{IMAGE_SUFFIX}"
        )
        if not image.is_file():
            raise NotFoundError(
                f"slot {slot_id!r} is declared but its image is missing "
                f"from {FINAL_IMAGES_DIRNAME}/ — run {app_id}/{run_id} "
                "is incomplete"
            )
        return image

    def _safe_run_dir(self, app_id: str, run_id: str) -> Path:
        """``apps_root/app_id/run_id``, but only if the ids are
        well-formed and the resolved path stays inside ``apps_root``
        (path-traversal guard)."""
        if not _ID_PATTERN.match(app_id) or not _RUN_ID_PATTERN.match(run_id):
            raise NotFoundError(f"no run {app_id}/{run_id}")
        apps_root = self._apps_root.resolve()
        run_dir = (apps_root / app_id / run_id).resolve()
        if apps_root not in run_dir.parents:
            raise NotFoundError(f"no run {app_id}/{run_id}")
        return run_dir


# Process-scoped singleton the router + FontService depend on. The
# default reads ``apps_root`` from Settings, and is rebuilt lazily so
# tests that override ``settings.apps_root`` before first call pick up
# the override automatically. Tests can also assign a fully-stub
# instance to ``_DEFAULT`` to bypass the filesystem entirely.
_DEFAULT: OutputService | None = None


def output_service() -> OutputService:
    """The one process-scoped OutputService, lazily built on first
    call. Reads ``apps_root`` from Settings at construction; reset
    ``_DEFAULT = None`` (or assign a stub) in tests if you change
    ``settings.apps_root`` after the first hit."""
    global _DEFAULT
    if _DEFAULT is None:
        _DEFAULT = OutputService(apps_root=settings.apps_root)
    return _DEFAULT
