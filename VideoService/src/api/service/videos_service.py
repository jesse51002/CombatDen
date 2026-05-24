"""VideosService — filesystem reads behind the API: list companies and load
one company's validated `videos_config.yaml`.

Company-agnostic: ``app_id`` is an opaque, pattern-checked string. The
``apps_root`` is injected so tests can point the service at a fixture tree
without monkeypatching module-level globals. The API process holds one
process-scoped instance (see ``videos_service`` below) reused across requests.
"""

from __future__ import annotations

import re
from pathlib import Path

import yaml
from pydantic import ValidationError

from schema import ClassOutput, VideosConfig, VideosOutput
from src.api.config import settings
from src.api.errors import InvalidConfigError, NotFoundError

CONFIG_FILENAME = "videos_config.yaml"
OUTPUT_FILENAME = "videos_output.yaml"
CLASS_FILENAME = "class_output.yaml"
# snake_case company ids; also a path-traversal guard (no dots or slashes).
_ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")


class VideosService:
    """Lists company briefs and loads one company's ``videos_config.yaml``.

    Constructor takes the apps root so tests can point at a fixture tree
    without monkeypatching ``settings.apps_root``.
    """

    def __init__(self, apps_root: Path) -> None:
        self._apps_root = apps_root

    async def list_apps(self) -> list[str]:
        """Every company id under ``apps_root`` that has a
        ``videos_config.yaml``. Sorted; never raises for an empty tree."""
        root = self._apps_root.resolve()
        if not root.is_dir():
            return []
        ids = [
            child.name
            for child in root.iterdir()
            if child.is_dir()
            and _ID_PATTERN.match(child.name)
            and (child / CONFIG_FILENAME).is_file()
        ]
        return sorted(ids)

    async def load(self, app_id: str) -> VideosConfig:
        """The company's validated ``videos_config.yaml``.

        Missing company/file -> ``NotFoundError`` (404). A file that is
        present but unparseable or stale against the current schema ->
        ``InvalidConfigError`` (422): the brief is real, the artifact just no
        longer conforms — that is not a server fault.
        """
        config_file = self._safe_app_dir(app_id) / CONFIG_FILENAME
        if not config_file.is_file():
            raise NotFoundError(f"no {CONFIG_FILENAME} for {app_id!r}")
        try:
            return VideosConfig.model_validate(
                yaml.safe_load(config_file.read_text())
            )
        except (yaml.YAMLError, ValidationError) as exc:
            raise InvalidConfigError(
                f"company {app_id!r} exists but its {CONFIG_FILENAME} does "
                "not match the current schema; regenerate it"
            ) from exc

    async def load_output(self, app_id: str) -> VideosOutput:
        """The company's validated ``videos_output.yaml`` (the batch result).

        Missing company, or a brief that hasn't been run through the batch
        script yet (no output file) -> ``NotFoundError`` (404). A file that is
        present but unparseable or stale -> ``InvalidConfigError`` (422).
        """
        output_file = self._safe_app_dir(app_id) / OUTPUT_FILENAME
        if not output_file.is_file():
            raise NotFoundError(
                f"no {OUTPUT_FILENAME} for {app_id!r}; run the batch script first"
            )
        try:
            return VideosOutput.model_validate(
                yaml.safe_load(output_file.read_text())
            )
        except (yaml.YAMLError, ValidationError) as exc:
            raise InvalidConfigError(
                f"company {app_id!r} has a {OUTPUT_FILENAME} but it does not "
                "match the current schema; regenerate it"
            ) from exc

    async def load_classes(self, app_id: str) -> ClassOutput:
        """The company's validated ``class_output.yaml`` (4 branded class cards).

        Missing company / file (the class-images skill hasn't run) ->
        ``NotFoundError`` (404). Present but unparseable or stale ->
        ``InvalidConfigError`` (422).
        """
        class_file = self._safe_app_dir(app_id) / CLASS_FILENAME
        if not class_file.is_file():
            raise NotFoundError(
                f"no {CLASS_FILENAME} for {app_id!r}; run the class-images step first"
            )
        try:
            return ClassOutput.model_validate(yaml.safe_load(class_file.read_text()))
        except (yaml.YAMLError, ValidationError) as exc:
            raise InvalidConfigError(
                f"company {app_id!r} has a {CLASS_FILENAME} but it does not "
                "match the current schema; regenerate it"
            ) from exc

    def _safe_app_dir(self, app_id: str) -> Path:
        """``apps_root/app_id``, but only if the id is well-formed and the
        resolved path stays directly inside ``apps_root`` (path-traversal
        guard)."""
        if not _ID_PATTERN.match(app_id):
            raise NotFoundError(f"no company {app_id!r}")
        apps_root = self._apps_root.resolve()
        app_dir = (apps_root / app_id).resolve()
        if app_dir.parent != apps_root:
            raise NotFoundError(f"no company {app_id!r}")
        return app_dir


# Process-scoped singleton the router depends on. Built lazily on first call so
# tests that override ``settings.apps_root`` (or assign a stub to ``_DEFAULT``)
# before first use pick the override up automatically.
_DEFAULT: VideosService | None = None


def videos_service() -> VideosService:
    """The one process-scoped VideosService, lazily built on first call.
    Reads ``apps_root`` from Settings at construction; reset ``_DEFAULT = None``
    (or assign a stub) in tests if you change ``settings.apps_root`` after the
    first hit."""
    global _DEFAULT
    if _DEFAULT is None:
        _DEFAULT = VideosService(apps_root=settings.apps_root)
    return _DEFAULT
