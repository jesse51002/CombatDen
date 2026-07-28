"""RunReader — resolve a studio run's on-disk assets, mid-run.

One job: turn ``(run_id, slot_id)`` into the PNG the image node just wrote.

It exists because the read API cannot answer this question during a run.
``OutputService.image_file`` loads the run's ``output.yaml`` first, and that
file is written only when the whole run finishes — so every mid-run request
404s there. (It also 307-redirects to the CDN by default, where a run made
thirty seconds ago on a laptop does not exist.) That is the read API being
right about its own job — it serves *finished* runs — not a bug to fix
there.

Done-ness here is the file itself: ``final_images/<slot_id>.png`` exists or
it does not. The image node writes exactly one file per slot at the end of
its own work (``ImageNode.run`` → ``BackgroundService.run``), so the file's
presence is the same signal the ``node_finished`` event carries.
"""

from __future__ import annotations

import asyncio
import logging
import re
from pathlib import Path

from src.core.run_context import FINAL_IMAGES_DIRNAME
from src.studio.config import settings
from src.studio.errors import UnknownRunError
from src.studio.service.run_registry import RunRegistry, run_registry

logger = logging.getLogger(__name__)

# snake_case slot ids, mirroring the rule AppFormat enforces on every slot.
SLOT_ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")
IMAGE_SUFFIX = ".png"


class RunReader:
    """Locates one studio run's produced files on disk."""

    def __init__(self, registry: RunRegistry, apps_root: Path) -> None:
        self._registry = registry
        self._apps_root = apps_root

    async def image_file(self, run_id: str, slot_id: str) -> Path:
        """The delivered PNG for one slot of this run.

        ``UnknownRunError`` for a malformed slot id, an unknown run, or a
        slot whose image has not been produced (yet). One exception type
        because they are one answer to the client: there is nothing to show
        here right now.
        """
        if not SLOT_ID_PATTERN.match(slot_id):
            raise UnknownRunError(f"invalid slot id {slot_id!r}")
        snapshot = await self._registry.snapshot(run_id)
        image = (
            self._apps_root
            / snapshot.app_id
            / snapshot.run_name
            / FINAL_IMAGES_DIRNAME
            / f"{slot_id}{IMAGE_SUFFIX}"
        )
        if not await asyncio.to_thread(image.is_file):
            raise UnknownRunError(
                f"slot {slot_id!r} has no image in run {run_id} yet"
            )
        return image


_reader: RunReader | None = None


def run_reader() -> RunReader:
    """The process-wide reader."""
    global _reader
    if _reader is None:
        _reader = RunReader(run_registry(), settings.apps_root)
    return _reader
