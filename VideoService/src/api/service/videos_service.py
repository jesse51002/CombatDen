"""VideosService — the single-tenant filesystem store behind the API + scripts.

Flat layout (no tenant nesting):

    <root>/gyms/<gym_id>.yaml      — the gyms (each owns its videos config,
                                     classes, rewards, and scan-cost history)
    <root>/videos/<video_id>.yaml — the shared video pool (a `list[VideoOutput]`,
                                     one file per video; no manifest wrapper)
    <root>/cost_log.yaml          — the append-only spend ledger

``root`` is injected so tests can point at a tmp tree. The API process holds one
process-scoped instance (see ``videos_service`` below). The theme→gym link is the
set of gym files (each gym carries its ``theme``); VideoService never reads
ThemeService.
"""

from __future__ import annotations

import asyncio
import re
from collections.abc import Iterable
from pathlib import Path

import yaml
from pydantic import ValidationError

try:  # libyaml — ~35x faster YAML parsing than the pure-Python loader
    from yaml import CSafeLoader as _FAST_LOADER
except ImportError:  # pragma: no cover - libyaml is virtually always present
    from yaml import SafeLoader as _FAST_LOADER

from schema import (
    CostEntry,
    Gym,
    GymCard,
    GymsPage,
    VideoOutput,
)
from schema.parent_gym_type import parent_of
from src.api.config import settings
from src.api.errors import InvalidConfigError, NotFoundError
from src.shared.util.video_id import video_id_from_url

GYMS_DIRNAME = "gyms"
VIDEOS_DIRNAME = "videos"
COST_LOG_FILENAME = "cost_log.yaml"
# Threads for load_videos_by_id: each does a disk read + libyaml parse (both
# release the GIL), so a small pool overlaps the IO and the parse.
_LOAD_WORKERS = 16
# A gym's card art is its theme's celebration image, served by ThemeService's
# styles convention (`/apps/<theme_app>/<run_id>/images/celebration_image`) and
# resolved by the client against the ThemeService base URL. DERIVED from the
# gym's theme. The themes this single tenant serves live under ThemeService's
# `combatden` app.
THEME_SERVICE_APP_ID = "combatden"
CELEBRATION_IMAGE_URL_TEMPLATE = (
    "/apps/" + THEME_SERVICE_APP_ID + "/{theme}/images/celebration_image"
)
# snake_case gym ids; also a path-traversal guard (no dots or slashes).
_ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")
# YouTube video ids — the per-video filename stem + a path-traversal guard.
_VIDEO_ID_PATTERN = re.compile(r"^[A-Za-z0-9_-]+$")


def _dump_yaml(data: object, path: Path) -> None:
    """Write ``data`` as YAML (insertion order preserved, unicode kept)."""
    path.write_text(
        yaml.safe_dump(
            data, sort_keys=False, allow_unicode=True, default_flow_style=False
        ),
        encoding="utf-8",
    )


class VideosService:
    """The single-tenant store: gyms, the shared video pool, and the cost log."""

    def __init__(self, root: Path) -> None:
        self._root = root

    @property
    def _gyms_dir(self) -> Path:
        return self._root / GYMS_DIRNAME

    @property
    def _videos_dir(self) -> Path:
        return self._root / VIDEOS_DIRNAME

    # --- gyms ----------------------------------------------------------------

    async def list_gyms(self) -> list[str]:
        """The gym ids that have a ``gyms/<id>.yaml`` file, sorted. Empty when
        there is no ``gyms/`` directory yet."""
        if not self._gyms_dir.is_dir():
            return []
        return sorted(f.stem for f in self._gyms_dir.glob("*.yaml"))

    async def load_gym(self, gym_id: str) -> Gym:
        """One gym by id. Missing -> ``NotFoundError``; stale ->
        ``InvalidConfigError``. ``gym_id`` is pattern-checked (no traversal)."""
        if not _ID_PATTERN.match(gym_id):
            raise NotFoundError(f"no gym {gym_id!r}")
        gym_file = self._gyms_dir / f"{gym_id}.yaml"
        if not gym_file.is_file():
            raise NotFoundError(f"no gym {gym_id!r}")
        try:
            return Gym.model_validate(yaml.safe_load(gym_file.read_text()))
        except (yaml.YAMLError, ValidationError) as exc:
            raise InvalidConfigError(
                f"gym {gym_id!r} does not match the current schema; regenerate it"
            ) from exc

    async def save_gym(self, gym: Gym) -> None:
        """Write (or overwrite) one gym's ``gyms/<gym_id>.yaml``."""
        if not _ID_PATTERN.match(gym.gym_id):
            raise InvalidConfigError(f"invalid gym_id {gym.gym_id!r}")
        self._gyms_dir.mkdir(parents=True, exist_ok=True)
        _dump_yaml(gym.model_dump(mode="json"), self._gyms_dir / f"{gym.gym_id}.yaml")

    async def list_gyms_page(
        self, *, limit: int, offset: int, query: str | None = None
    ) -> GymsPage:
        """One page of slim gym cards for the gym browser, sorted by gym id.
        ``query`` is an optional case-insensitive substring filter on gym id /
        theme / discipline. Empty page (not 404) when there are no gyms (or none
        match); a stale gym file -> ``InvalidConfigError``."""
        gyms = [await self.load_gym(gid) for gid in await self.list_gyms()]
        if query:
            needle = query.strip().lower()
            gyms = [
                g
                for g in gyms
                if needle in g.gym_id.lower()
                or needle in g.theme.lower()
                or any(needle in t.value for t in g.gym_type)
            ]
        total = len(gyms)
        cards = [
            GymCard(
                gym_id=gym.gym_id,
                gym_type=gym.gym_type,
                # Coarse parent bucket from the primary discipline — the filter
                # category the gym browser groups by.
                parent_gym_type=parent_of(gym.gym_type[0]),
                theme=gym.theme,
                # Derived from the theme; the client resolves it against the
                # ThemeService base URL, same as the theme picker.
                celebration_image_url=CELEBRATION_IMAGE_URL_TEMPLATE.format(
                    theme=gym.theme
                ),
                video_count=len(gym.videos.good_video_ids),
                has_classes=gym.classes is not None,
                has_rewards=gym.rewards is not None,
            )
            for gym in gyms[offset : offset + limit]
        ]
        return GymsPage(total=total, limit=limit, offset=offset, gyms=cards)

    # --- the shared video pool ----------------------------------------------

    async def load_pool(self) -> list[VideoOutput]:
        """The whole shared pool — every ``videos/<id>.yaml`` — in a stable
        ``(relevance_index, video_id)`` order. Empty when there is no pool yet;
        a stale per-video file -> ``InvalidConfigError``."""
        if not self._videos_dir.is_dir():
            return []
        try:
            videos = [
                VideoOutput.model_validate(yaml.safe_load(f.read_text()))
                for f in sorted(self._videos_dir.glob("*.yaml"))
            ]
        except (yaml.YAMLError, ValidationError) as exc:
            raise InvalidConfigError(
                "a pooled video file does not match the current schema; "
                "regenerate it"
            ) from exc
        videos.sort(key=lambda v: (v.relevance_index, video_id_from_url(v.url)))
        return videos

    async def load_videos_by_id(
        self, ids: Iterable[str]
    ) -> dict[str, VideoOutput]:
        """Load ONLY the named pool videos (skipping the rest of the pool), keyed
        by id. Each read is a disk read + libyaml parse; they run across a small
        thread pool (``_LOAD_WORKERS``) so the IO and the GIL-releasing parse
        overlap instead of blocking the event loop one file at a time. A missing
        or stale file is skipped — the caller simply won't get that id. Use this
        when you already know which ids you need (e.g. a gym's good/rejected feed)
        rather than paying to load the whole pool."""
        wanted = [i for i in dict.fromkeys(ids) if _VIDEO_ID_PATTERN.match(i)]
        if not wanted:
            return {}

        def _read_chunk(chunk: list[str]) -> dict[str, VideoOutput]:
            out: dict[str, VideoOutput] = {}
            for vid in chunk:
                path = self._videos_dir / f"{vid}.yaml"
                try:
                    data = yaml.load(path.read_text(encoding="utf-8"), Loader=_FAST_LOADER)
                    out[vid] = VideoOutput.model_validate(data)
                except (OSError, yaml.YAMLError, ValidationError):
                    continue  # missing / stale -> omit; the card just won't show
            return out

        chunks = [wanted[i::_LOAD_WORKERS] for i in range(_LOAD_WORKERS)]
        maps = await asyncio.gather(
            *(asyncio.to_thread(_read_chunk, chunk) for chunk in chunks if chunk)
        )
        merged: dict[str, VideoOutput] = {}
        for part in maps:
            merged.update(part)
        return merged

    async def save_pool(self, videos: list[VideoOutput]) -> None:
        """Replace the whole pool: clear ``videos/`` and write one file per
        video. A fresh fetch is a full replacement."""
        self._videos_dir.mkdir(parents=True, exist_ok=True)
        for stale in self._videos_dir.glob("*.yaml"):
            stale.unlink()
        for video in videos:
            self._write_video(video)

    async def save_video(self, video: VideoOutput) -> None:
        """Write (or overwrite) one pooled video — the cheap partial update the
        tagging pass uses so it never rewrites the whole pool."""
        self._write_video(video)

    async def list_video_ids(self) -> list[str]:
        """The pooled video ids, sorted. Empty when there is no pool yet."""
        if not self._videos_dir.is_dir():
            return []
        return sorted(f.stem for f in self._videos_dir.glob("*.yaml"))

    async def load_video(self, video_id: str) -> VideoOutput:
        """One pooled video by id. Missing -> ``NotFoundError``."""
        video_file = self._video_path(video_id)
        if not video_file.is_file():
            raise NotFoundError(f"no video {video_id!r}")
        try:
            return VideoOutput.model_validate(yaml.safe_load(video_file.read_text()))
        except (yaml.YAMLError, ValidationError) as exc:
            raise InvalidConfigError(
                f"video {video_id!r} does not match the current schema"
            ) from exc

    async def load_videos(self, video_ids: list[str]) -> list[VideoOutput]:
        """Load the given pooled videos **by id** (the filename stem), preserving
        the given order and skipping any id with no file. Reads only those files —
        never the whole pool — so serving a gym's feed costs O(feed size), not
        O(pool size). A *stale* file still raises ``InvalidConfigError``."""
        out: list[VideoOutput] = []
        for vid in video_ids:
            try:
                out.append(await self.load_video(vid))
            except NotFoundError:
                continue  # id not in the pool (or malformed) — skip, as before
        return out

    async def delete_video(self, video_id: str) -> bool:
        """Remove one pooled video's file. Returns whether a file was removed."""
        video_file = self._video_path(video_id)
        if not video_file.is_file():
            return False
        video_file.unlink()
        return True

    def _write_video(self, video: VideoOutput) -> None:
        video_id = video_id_from_url(video.url)
        if not video_id:
            raise InvalidConfigError(f"video has no id in its url: {video.url!r}")
        self._videos_dir.mkdir(parents=True, exist_ok=True)
        _dump_yaml(video.model_dump(mode="json"), self._videos_dir / f"{video_id}.yaml")

    def _video_path(self, video_id: str) -> Path:
        if not _VIDEO_ID_PATTERN.match(video_id):
            raise NotFoundError(f"no video {video_id!r}")
        return self._videos_dir / f"{video_id}.yaml"

    # --- cost ledger ---------------------------------------------------------

    async def append_cost(self, entry: CostEntry) -> None:
        """Append one entry to the append-only ``cost_log.yaml`` ledger (created
        on first append). Never overwrites prior entries."""
        log_file = self._root / COST_LOG_FILENAME
        existing: list[dict] = []
        if log_file.is_file():
            loaded = yaml.safe_load(log_file.read_text())
            if isinstance(loaded, list):
                existing = loaded
        existing.append(entry.model_dump(mode="json"))
        log_file.parent.mkdir(parents=True, exist_ok=True)
        _dump_yaml(existing, log_file)

    async def load_cost_log(self) -> list[CostEntry]:
        """The cost ledger as validated entries (empty if none yet)."""
        log_file = self._root / COST_LOG_FILENAME
        if not log_file.is_file():
            return []
        loaded = yaml.safe_load(log_file.read_text()) or []
        return [CostEntry.model_validate(e) for e in loaded]


# Process-scoped singleton the router depends on. Built lazily on first call so
# tests that override ``settings.data_root`` (or assign a stub to ``_DEFAULT``)
# before first use pick the override up automatically.
_DEFAULT: VideosService | None = None


def videos_service() -> VideosService:
    """The one process-scoped VideosService, lazily built on first call. Reads
    ``data_root`` from Settings; reset ``_DEFAULT = None`` (or assign a stub) in
    tests if you change ``settings.data_root`` after the first hit."""
    global _DEFAULT
    if _DEFAULT is None:
        _DEFAULT = VideosService(root=settings.data_root)
    return _DEFAULT
