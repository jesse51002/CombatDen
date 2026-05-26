"""VideosService — the filesystem store behind the API and the batch scripts.

Reads companies and their briefs, and owns the **split-file feed layout**: each
app's fetched feed is a metadata-only manifest (``videos_output.yaml``, a
``VideosManifest``) plus one file per video under ``videos/`` (a ``VideoOutput``,
with its full transcript as the last key). ``load_output`` reassembles a single
``VideosOutput`` from the two so consumers keep seeing one aggregate; the write
helpers (``save_output``/``save_video``/``delete_video``) keep the layout in one
place. Centralising it here eases the eventual fold into ``FastApiBackend``.

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

from schema import ClassOutput, VideoOutput, VideosConfig, VideosManifest, VideosOutput
from src.api.config import settings
from src.api.errors import InvalidConfigError, NotFoundError
from src.shared.util.video_id import video_id_from_url

CONFIG_FILENAME = "videos_config.yaml"
# The per-app run manifest (metadata only); the videos themselves live one per
# file under VIDEOS_DIRNAME/.
OUTPUT_FILENAME = "videos_output.yaml"
VIDEOS_DIRNAME = "videos"
CLASS_FILENAME = "class_output.yaml"
# snake_case company ids; also a path-traversal guard (no dots or slashes).
_ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")
# YouTube video ids — the per-video filename stem; also a path-traversal guard
# (no dots or slashes, so it can't escape the videos/ directory).
_VIDEO_ID_PATTERN = re.compile(r"^[A-Za-z0-9_-]+$")


def _dump_yaml(data: object, path: Path) -> None:
    """Write ``data`` as YAML the way every writer in this service does
    (insertion order preserved, unicode kept, block style)."""
    path.write_text(
        yaml.safe_dump(
            data, sort_keys=False, allow_unicode=True, default_flow_style=False
        ),
        encoding="utf-8",
    )


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
        """The company's fetched feed, reassembled from the manifest plus every
        per-video file under ``videos/`` into one ``VideosOutput``.

        Missing company, or a brief that hasn't been run through the batch
        script yet (no manifest) -> ``NotFoundError`` (404). A manifest or a
        per-video file that is present but unparseable or stale ->
        ``InvalidConfigError`` (422). Videos are returned in a deterministic
        ``(relevance_index, video_id)`` order so pagination is stable.
        """
        app_dir = self._safe_app_dir(app_id)
        manifest_file = app_dir / OUTPUT_FILENAME
        if not manifest_file.is_file():
            raise NotFoundError(
                f"no {OUTPUT_FILENAME} for {app_id!r}; run the batch script first"
            )
        try:
            manifest = VideosManifest.model_validate(
                yaml.safe_load(manifest_file.read_text())
            )
            videos = [
                VideoOutput.model_validate(yaml.safe_load(f.read_text()))
                for f in sorted((app_dir / VIDEOS_DIRNAME).glob("*.yaml"))
            ]
        except (yaml.YAMLError, ValidationError) as exc:
            raise InvalidConfigError(
                f"company {app_id!r} has a {OUTPUT_FILENAME} (or a per-video "
                "file) that does not match the current schema; regenerate it"
            ) from exc
        videos.sort(key=lambda v: (v.relevance_index, video_id_from_url(v.url)))
        return VideosOutput(**manifest.model_dump(), videos=videos)

    async def save_output(self, app_id: str, output: VideosOutput) -> None:
        """Persist a whole fetched feed: write the manifest and one file per
        video, replacing any previous feed for this app. Used by the YouTube
        batch — a fresh fetch is a full replacement, so stale per-video files
        from a prior run are cleared first (the ``videos_output.removed.yaml``
        audit log is untouched)."""
        app_dir = self._safe_app_dir(app_id)
        videos_dir = app_dir / VIDEOS_DIRNAME
        videos_dir.mkdir(parents=True, exist_ok=True)
        for stale in videos_dir.glob("*.yaml"):
            stale.unlink()
        self._write_manifest(app_dir, output)
        for video in output.videos:
            self._write_video(app_dir, video)

    async def save_manifest(self, app_id: str, output: VideosOutput) -> None:
        """Rewrite just the run manifest (metadata: counts, costs) from
        ``output``'s fields, leaving every per-video file untouched. Used by the
        classify pass to record its cost without rewriting the feed."""
        self._write_manifest(self._safe_app_dir(app_id), output)

    async def save_video(self, app_id: str, video: VideoOutput) -> None:
        """Write (or overwrite) one video's file, leaving the manifest and every
        other video untouched. The cheap partial update the transcripts and
        classify passes use so they never rewrite the whole feed."""
        self._write_video(self._safe_app_dir(app_id), video)

    async def list_video_ids(self, app_id: str) -> list[str]:
        """The video ids that have a per-video file, sorted. Empty when the app
        has no ``videos/`` directory yet."""
        videos_dir = self._safe_app_dir(app_id) / VIDEOS_DIRNAME
        if not videos_dir.is_dir():
            return []
        return sorted(f.stem for f in videos_dir.glob("*.yaml"))

    async def load_video(self, app_id: str, video_id: str) -> VideoOutput:
        """One video by id. Missing -> ``NotFoundError``; stale ->
        ``InvalidConfigError``."""
        video_file = self._video_path(app_id, video_id)
        if not video_file.is_file():
            raise NotFoundError(f"no video {video_id!r} for {app_id!r}")
        try:
            return VideoOutput.model_validate(yaml.safe_load(video_file.read_text()))
        except (yaml.YAMLError, ValidationError) as exc:
            raise InvalidConfigError(
                f"video {video_id!r} for {app_id!r} does not match the current "
                "schema; regenerate it"
            ) from exc

    async def delete_video(self, app_id: str, video_id: str) -> bool:
        """Remove one video's file. Returns whether a file was actually
        removed (False when nothing matched the id)."""
        video_file = self._video_path(app_id, video_id)
        if not video_file.is_file():
            return False
        video_file.unlink()
        return True

    def _write_manifest(self, app_dir: Path, output: VideosOutput) -> None:
        """Write the metadata-only manifest from ``output``'s non-video fields."""
        manifest = VideosManifest.model_validate(output.model_dump(exclude={"videos"}))
        _dump_yaml(manifest.model_dump(mode="json"), app_dir / OUTPUT_FILENAME)

    def _write_video(self, app_dir: Path, video: VideoOutput) -> None:
        """Write one ``VideoOutput`` to ``videos/<video_id>.yaml``."""
        video_id = video_id_from_url(video.url)
        if not video_id:
            raise InvalidConfigError(f"video has no id in its url: {video.url!r}")
        videos_dir = app_dir / VIDEOS_DIRNAME
        videos_dir.mkdir(parents=True, exist_ok=True)
        _dump_yaml(video.model_dump(mode="json"), videos_dir / f"{video_id}.yaml")

    def _video_path(self, app_id: str, video_id: str) -> Path:
        """``apps_root/app_id/videos/<video_id>.yaml`` — id pattern-checked so it
        can't escape the videos directory."""
        if not _VIDEO_ID_PATTERN.match(video_id):
            raise NotFoundError(f"no video {video_id!r}")
        return self._safe_app_dir(app_id) / VIDEOS_DIRNAME / f"{video_id}.yaml"

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
