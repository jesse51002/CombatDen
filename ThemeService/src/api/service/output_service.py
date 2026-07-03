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

import asyncio
import hashlib
import logging
import re
from pathlib import Path

import yaml
from pydantic import ValidationError

from schema import Output
from schema.app_format import AppFormat
from src.api.config import settings
from src.api.errors import InvalidRunError, NotFoundError
from src.api.schema.style_list_response import StyleListResponse
from src.api.schema.style_summary import StyleSummary
from src.core.asset_urls import cdn_url, image_key
from src.core.errors import PipelineError
from src.core.run_context import (
    APP_FILENAME,
    FINAL_IMAGES_DIRNAME,
    ICONS_DIRNAME,
    OUTPUT_FILENAME,
)
from src.core.util import load_yaml

logger = logging.getLogger(__name__)

# Run-dir layout — `output.yaml`, `final_images/` (the one place a delivered
# per-slot PNG lives; `images/` raw+cutout intermediates are never served)
# and `icons/` (per-slot SVGs) — is
# owned by src.core.run_context. The pipeline writes runs against those
# constants, so the API reads them back from the same source rather than
# redefining them.
IMAGE_SUFFIX = ".png"
ICON_SUFFIX = ".svg"
# The image slot a style picker shows as each style's card art.
CELEBRATION_SLOT = "celebration_image"


def _content_version(path: Path) -> str:
    """Short sha256 of a file's bytes — the cache-bust ``?v=`` token (matches
    the writer's stamp). ``""`` if the file is absent (nothing to fingerprint)."""
    if not path.is_file():
        return ""
    return hashlib.sha256(path.read_bytes()).hexdigest()[:12]

# snake_case ids (mirrors schema.output.Output's app/slot rule).
_ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")
# Run ids are UTC stamps like `20260517T052107Z` — alphanumeric only.
_RUN_ID_PATTERN = re.compile(r"^[0-9A-Za-z]+$")
# Date-stamped pipeline runs (e.g. `20260518T131056Z`). A style picker
# lists only the named presets, never these transient run dirs.
_RUN_STAMP_PATTERN = re.compile(r"^\d{8}T\d{6}Z$")


class OutputService:
    """Loads a run's ``output.yaml`` and resolves declared per-slot
    image paths on disk.

    Constructor takes the apps root so tests can point at the fixture
    tree without monkeypatching ``settings.apps_root``.
    """

    def __init__(self, apps_root: Path) -> None:
        self._apps_root = apps_root
        # Cache for `list_styles`: the full sorted [StyleSummary] per
        # app, keyed by app_id, with the captured directory mtime AND
        # the app.yaml file mtime (an app.yaml category edit changes the
        # file's mtime but not the dir's) so either kind of change
        # invalidates the entry. Without this every page request would
        # re-scan the apps tree and Pydantic-validate every output.yaml
        # — fine for ~5 styles, painful for 80+. (In-place edits to an
        # output.yaml don't bump the parent dir mtime, so a
        # regen/edit_customization run wants an API process restart to
        # be reflected — acceptable for the current admin-tool
        # deployment.)
        self._styles_cache: dict[
            str, tuple[tuple[int, int], list[StyleSummary]]
        ] = {}

    async def load(self, app_id: str, run_id: str) -> Output:
        """The run's validated ``output.yaml``.

        Missing run/file -> ``NotFoundError`` (404). A file that is
        present but unparseable or stale against the current schema ->
        ``InvalidRunError`` (422): the run is real, the artifact just
        no longer conforms — that is not a server fault.
        """
        output_file = self._safe_run_dir(app_id, run_id) / OUTPUT_FILENAME
        if not await asyncio.to_thread(output_file.is_file):
            raise NotFoundError(f"no output for {app_id}/{run_id}")
        try:
            raw = await asyncio.to_thread(output_file.read_text)
            return Output.model_validate(yaml.safe_load(raw))
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
        if not await asyncio.to_thread(image.is_file):
            raise NotFoundError(
                f"slot {slot_id!r} is declared but its image is missing "
                f"from {FINAL_IMAGES_DIRNAME}/ — run {app_id}/{run_id} "
                "is incomplete"
            )
        return image

    async def icon_file(
        self, app_id: str, run_id: str, slot_id: str
    ) -> Path:
        """The on-disk SVG for one declared icon slot.

        Exactly ``<run_dir>/icons/<slot_id>.svg`` — the one place the icon
        module writes a slot's resolved (matched or generated) SVG. Same
        three-case 404 contract as :meth:`image_file`: malformed slot id,
        slot not declared in the run's ``output.yaml``, or declared but its
        SVG is absent (an incomplete run).
        """
        if not _ID_PATTERN.match(slot_id):
            raise NotFoundError(f"invalid slot id {slot_id!r}")
        output = await self.load(app_id, run_id)
        if slot_id not in output.icon_set.icons:
            raise NotFoundError(
                f"icon slot {slot_id!r} is not declared in run "
                f"{app_id}/{run_id}"
            )
        icon = (
            self._safe_run_dir(app_id, run_id)
            / ICONS_DIRNAME
            / f"{slot_id}{ICON_SUFFIX}"
        )
        if not await asyncio.to_thread(icon.is_file):
            raise NotFoundError(
                f"icon slot {slot_id!r} is declared but its SVG is missing "
                f"from {ICONS_DIRNAME}/ — run {app_id}/{run_id} is incomplete"
            )
        return icon

    async def list_styles(
        self,
        app_id: str,
        *,
        offset: int = 0,
        limit: int = 20,
        query: str | None = None,
    ) -> StyleListResponse:
        """One page of the app's named, selectable styles.

        Same selection rules as before: skips the
        ``YYYYMMDDTHHMMSSZ`` run dirs, any dir without a valid
        ``output.yaml``, and any whose ``celebration_image`` PNG is
        absent (so every entry has card art). A stale ``output.yaml``
        is skipped, not surfaced — a bad preset shouldn't 500 the
        whole list. Sorted by display name.

        ``query`` is a case-insensitive substring match against the
        run id and the resolved display name; ``None`` / empty match
        everything. Filtering happens before slicing, so ``total``
        is the post-filter count.

        404 (``NotFoundError``) when the app itself is unknown.
        """
        if not _ID_PATTERN.match(app_id):
            raise NotFoundError(f"no app {app_id!r}")
        apps_root = self._apps_root.resolve()
        app_dir = (apps_root / app_id).resolve()
        if app_dir.parent != apps_root or not await asyncio.to_thread(app_dir.is_dir):
            raise NotFoundError(f"no app {app_id!r}")

        all_styles = await self._cached_full_style_list(app_id, app_dir)

        needle = (query or "").strip().casefold()
        if needle:
            filtered = [
                s for s in all_styles
                if needle in s.display_name.casefold()
                or needle in s.id.casefold()
            ]
        else:
            filtered = all_styles
        total = len(filtered)
        page = filtered[offset : offset + limit]
        return StyleListResponse(
            items=page, total=total, offset=offset, limit=limit
        )

    async def _cached_full_style_list(
        self, app_id: str, app_dir: Path
    ) -> list[StyleSummary]:
        """Return the full sorted style list for ``app_id``, building
        it on cache miss and reusing the cached copy when neither the
        apps dir mtime nor the app.yaml mtime has changed."""
        dir_mtime = (await asyncio.to_thread(app_dir.stat)).st_mtime_ns
        app_yaml = app_dir / APP_FILENAME
        yaml_mtime = (
            (await asyncio.to_thread(app_yaml.stat)).st_mtime_ns
            if await asyncio.to_thread(app_yaml.is_file)
            else 0
        )
        key = (dir_mtime, yaml_mtime)
        cached = self._styles_cache.get(app_id)
        if cached is not None and cached[0] == key:
            return cached[1]
        built = await self._build_full_style_list(app_id, app_dir)
        self._styles_cache[app_id] = (key, built)
        return built

    async def _declared_categories(self, app_dir: Path) -> set[str]:
        """The app.yaml-declared classification vocabulary (the closed
        set a run's ``output.yaml`` ``category`` must belong to).
        ``set()`` when the app.yaml is absent, unparseable, or declares
        no categories — the vocabulary check is then skipped (an app
        with no classification concept still lists categorised runs
        as-is), consistent with the skip-a-bad-preset rule above.

        ``load_yaml`` (the package's one YAML read) is off-loaded to a
        thread so its blocking file read never touches the event loop; it
        raises ``PipelineError`` for an absent, unreadable, malformed, or
        non-mapping file — all swallowed to ``set()`` here, same as an
        invalid ``AppFormat``."""
        app_yaml = app_dir / APP_FILENAME
        try:
            raw = await asyncio.to_thread(load_yaml, app_yaml)
            app_format = AppFormat.model_validate(raw)
        except (PipelineError, ValidationError):
            return set()
        return set(app_format.categories)

    async def _build_full_style_list(
        self, app_id: str, app_dir: Path
    ) -> list[StyleSummary]:
        """Scan every named run dir under ``app_dir`` and resolve it
        into a ``StyleSummary``. Same selection + sort rules as the
        public list_styles (date-stamped runs skipped, missing
        output.yaml / celebration_image PNG skipped, stale output.yaml
        skipped). Expensive — one ``load()`` per surviving dir —
        which is why callers go through the cache."""
        cdn = settings.assets_cdn_base_url
        candidates = await asyncio.to_thread(
            self._scan_candidate_dirs, app_dir, not cdn
        )
        declared_categories = await self._declared_categories(app_dir)
        styles: list[StyleSummary] = []
        for run_id, celebration in candidates:
            try:
                output = await self.load(app_id, run_id)
            except (NotFoundError, InvalidRunError):
                continue
            # Category is REQUIRED on the wire: an uncategorised run —
            # or one whose category isn't in the app.yaml-declared
            # vocabulary — is skipped, not listed unfilterable. Warn (once
            # per run per list build — this loop is cache-gated) so a
            # dropped theme isn't silent: today categories are hand-stamped,
            # so a missing/typo'd stamp is the likely cause of a run vanishing
            # from the picker.
            category = output.category
            if category is None:
                logger.warning(
                    "style list: skipping run %s/%s — no category stamped "
                    "on its output.yaml",
                    app_id,
                    run_id,
                )
                continue
            if declared_categories and category not in declared_categories:
                logger.warning(
                    "style list: skipping run %s/%s — category %r is not in "
                    "the app.yaml-declared vocabulary %s",
                    app_id,
                    run_id,
                    category,
                    sorted(declared_categories),
                )
                continue
            # Card-art `?v=` cache-buster: prefer the stamped slot version from
            # output.yaml; locally fall back to hashing the on-disk PNG.
            celebration_slot = output.image_set.images.get(CELEBRATION_SLOT)
            # Under a CDN there is no on-disk PNG to fall back on, so the
            # celebration card art must be declared in output.yaml to qualify.
            if cdn and celebration_slot is None:
                continue
            version = (
                celebration_slot.version
                if celebration_slot and celebration_slot.version
                else _content_version(celebration)
            )
            if cdn:
                celebration_image = cdn_url(
                    cdn, image_key(app_id, run_id, CELEBRATION_SLOT), version
                )
            else:
                celebration_image = (
                    f"/apps/{app_id}/{run_id}/images/{CELEBRATION_SLOT}"
                )
                if version:
                    celebration_image = f"{celebration_image}?v={version}"
            styles.append(
                StyleSummary(
                    id=run_id,
                    display_name=output.design_name,
                    celebration_image=celebration_image,
                    category=category,
                )
            )
        styles.sort(key=lambda s: s.display_name)
        return styles

    @staticmethod
    def _scan_candidate_dirs(
        app_dir: Path, require_celebration_file: bool
    ) -> list[tuple[str, Path]]:
        """Synchronous scan of ``app_dir`` — returns ``(run_id, celebration_path)``
        pairs that pass the filesystem pre-filters (named dir, non-stamp id,
        output.yaml present). When ``require_celebration_file`` (local serving,
        no CDN) a dir also needs its celebration PNG on disk; under a CDN the
        bytes live on S3, so that gate moves to the declared-slot check in the
        caller. Called via ``asyncio.to_thread`` so no blocking I/O touches the
        event loop."""
        candidates: list[tuple[str, Path]] = []
        for child in sorted(app_dir.iterdir()):
            run_id = child.name
            if not child.is_dir() or _RUN_STAMP_PATTERN.match(run_id):
                continue
            if not _RUN_ID_PATTERN.match(run_id):
                continue
            if not (child / OUTPUT_FILENAME).is_file():
                continue
            celebration = (
                child / FINAL_IMAGES_DIRNAME / f"{CELEBRATION_SLOT}{IMAGE_SUFFIX}"
            )
            if require_celebration_file and not celebration.is_file():
                continue
            candidates.append((run_id, celebration))
        return candidates

    def _safe_run_dir(self, app_id: str, run_id: str) -> Path:
        """``apps_root/app_id/run_id`` for well-formed ids.

        Path traversal is impossible by construction: both id patterns
        admit only alphanumerics/underscores — no separators, no dots —
        so the joined path cannot escape ``apps_root``. The path is
        deliberately NOT resolve()-contained: a run dir may be a
        SYMLINK to another checkout's data (worktrees link the large
        untracked run dirs from the root checkout via
        ``setup_worktree_env.sh``), and resolving would reject exactly
        those links."""
        if not _ID_PATTERN.match(app_id) or not _RUN_ID_PATTERN.match(run_id):
            raise NotFoundError(f"no run {app_id}/{run_id}")
        return self._apps_root / app_id / run_id


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
