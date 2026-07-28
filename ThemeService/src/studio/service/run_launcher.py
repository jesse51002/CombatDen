"""RunLauncher — validate a launch, start it, and let the caller watch.

The studio's whole job in one class: check that a launch is legal, reserve
the single run slot, kick the pipeline off in a background task, and return
immediately with a run id. A full run is minutes of provider calls and about
a dollar of real money, so nothing here blocks an HTTP request on it.

**The launch path only ever CREATES a run directory.** A name that already
exists is refused (``RunNameTakenError``), never re-run in place — so
``Pipeline._overwrite_existing``'s delete path is unreachable from the
browser. That is deliberate: it is the one code path in this package that
can destroy generated work.
"""

from __future__ import annotations

import asyncio
import logging
from pathlib import Path

from schema import AppFormat, Customization
from src.core.run_context import APP_FILENAME, RunContext
from src.core.util import load_yaml
from src.executor.orchestrator import Pipeline
from src.executor.writer import Writer
from src.studio.config import settings
from src.studio.errors import RunNameTakenError, UnknownAppError
from src.studio.schema.launch_request import LaunchAccepted, LaunchRequest
from src.studio.schema.run_status import RunStatus
from src.studio.service.brief_service import BriefService, brief_service
from src.studio.service.run_registry import RunRegistry, run_registry

logger = logging.getLogger(__name__)


class RunLauncher:
    """Starts one pipeline run per request, at most one at a time."""

    def __init__(
        self,
        registry: RunRegistry,
        briefs: BriefService,
        apps_root: Path,
    ) -> None:
        self._registry = registry
        self._briefs = briefs
        self._apps_root = apps_root
        # Background tasks are only weakly referenced by the event loop, so
        # a run could be garbage-collected mid-flight. Hold each until it
        # finishes.
        self._tasks: set[asyncio.Task[None]] = set()

    async def launch(self, request: LaunchRequest) -> LaunchAccepted:
        """Validate, reserve the run slot, and start generating.

        Every refusal happens before anything is created:
        ``UnknownAppError`` (no such app.yaml), ``UnknownBriefError`` (no
        such saved brief), ``RunNameTakenError`` (that run folder exists) and
        ``RunInFlightError`` (a run is already going).
        """
        app_id = request.app_id
        run_name = str(request.run_name)
        app = await self._load_app(app_id)
        cust = await self._resolve_brief(request)

        target = self._apps_root / app_id / run_name
        if await asyncio.to_thread(target.exists):
            raise RunNameTakenError(
                f"{app_id}/{run_name} already exists — the studio only ever "
                "creates new runs, it never overwrites one. Pick another "
                "name (or clear that folder yourself)."
            )

        snapshot = await self._registry.open(app_id=app_id, run_name=run_name)
        task = asyncio.create_task(
            self._generate(snapshot.run_id, app, cust, run_name)
        )
        self._tasks.add(task)
        task.add_done_callback(self._tasks.discard)
        logger.info(
            "launched run %s: %s/%s", snapshot.run_id, app_id, run_name
        )
        return LaunchAccepted(
            run_id=snapshot.run_id,
            app_id=app_id,
            run_name=run_name,
            status=snapshot.status,
            started_at=snapshot.started_at,
        )

    async def _generate(
        self,
        run_id: str,
        app: AppFormat,
        cust: Customization,
        run_name: str,
    ) -> None:
        """The background run: pipeline → writer → settle.

        Exactly the CLI's sequence (``src/cli.py``), with the registry as
        the progress sink and no ``prior_category`` — a brand-new run dir has
        no ``output.yaml`` to carry one from.

        Every failure settles the run as ``FAILED`` with the error text, so
        a watching client always sees a terminal record. A crash violent
        enough to skip even this is what the non-terminal log identifies.
        """
        try:
            run_ctx = RunContext(app, cust, self._apps_root, run_id=run_name)
            result = await Pipeline().run(
                run_ctx, progress=self._registry.sink(run_id)
            )
            # The writer is synchronous file I/O (yaml dumps + a sha256 per
            # asset). In a server that would block the event loop for every
            # other request, so it runs off-loop — the CLI can afford to
            # call it inline, the studio cannot.
            await asyncio.to_thread(Writer().write, result, run_ctx)
            await self._registry.settle(run_id, status=RunStatus.SUCCEEDED)
        except Exception as exc:  # noqa: BLE001 - reported, never swallowed
            logger.exception("run %s failed", run_id)
            await self._registry.settle(
                run_id,
                status=RunStatus.FAILED,
                error=f"{type(exc).__name__}: {exc}",
            )

    async def _load_app(self, app_id: str) -> AppFormat:
        """The app's slot manifest, or ``UnknownAppError``.

        The path is checked by identity, not by pattern: the resolved
        ``apps/<app_id>/`` must still be inside the resolved apps root, so
        no ``app_id`` can walk out of the tree. ``AppFormat`` then enforces
        the snake_case id rule on the file's own contents.
        """
        app_dir = (self._apps_root / app_id).resolve()
        if not app_dir.is_relative_to(self._apps_root.resolve()):
            raise UnknownAppError(f"no such app {app_id!r}")
        app_yaml = app_dir / APP_FILENAME
        if not await asyncio.to_thread(app_yaml.is_file):
            raise UnknownAppError(
                f"no such app {app_id!r} (expected {app_yaml})"
            )
        raw = await asyncio.to_thread(load_yaml, app_yaml)
        return AppFormat.model_validate(raw)

    async def _resolve_brief(self, request: LaunchRequest) -> Customization:
        """The brief to run from: the inline one, or the saved one.

        ``LaunchRequest`` already guaranteed exactly one of the two is set.
        """
        if request.brief is not None:
            return request.brief
        return await self._briefs.load(str(request.brief_slug))


_launcher: RunLauncher | None = None


def run_launcher() -> RunLauncher:
    """The process-wide launcher (it holds the in-flight task refs)."""
    global _launcher
    if _launcher is None:
        _launcher = RunLauncher(
            run_registry(), brief_service(), settings.apps_root
        )
    return _launcher
