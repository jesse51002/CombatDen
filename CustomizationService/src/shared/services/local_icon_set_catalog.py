"""LocalIconSetCatalog — IconSetCatalog backed by curated SVGs on disk.

Icon sets are shipped/curated files, not a network resource, so the
catalog is file-backed: each set is a directory under ``root`` with a
``set.yaml`` (the catalog metadata) and an ``icons/`` folder of
monochrome SVGs::

    <root>/<set_id>/set.yaml
    <root>/<set_id>/icons/<icon_name>.svg

The load is lazy and serialised by an ``asyncio.Lock`` (mirroring the
Google Fonts catalog) so concurrent callers on cold start don't all scan
the tree. There is no TTL — local files don't change under a running
process — so a single load per instance is enough.
"""

from __future__ import annotations

import asyncio
import logging
from pathlib import Path

import yaml

from schema.primitives import AbsolutePath
from src.core.errors import ProviderError
from src.shared.interfaces.icon_set_catalog import (
    IconSetCatalog,
    IconSetCatalogEntry,
)

logger = logging.getLogger(__name__)

SET_MANIFEST_NAME = "set.yaml"
ICONS_DIRNAME = "icons"


class LocalIconSetCatalog(IconSetCatalog):
    """Curated icon-set catalog backed by a directory tree of SVGs.

    ``root`` is the directory holding one subdirectory per set. The set
    id is the subdirectory name and must match the ``id`` in its
    ``set.yaml``. The load is one-shot (no TTL) behind a lock.
    """

    def __init__(self, root: Path) -> None:
        self._root = root
        # set_id -> entry. Empty until first load.
        self._by_id: dict[str, IconSetCatalogEntry] = {}
        self._loaded = False
        self._lock = asyncio.Lock()

    async def sets(self) -> list[IconSetCatalogEntry]:
        await self._ensure_loaded()
        return list(self._by_id.values())

    async def lookup(self, set_id: str) -> IconSetCatalogEntry | None:
        await self._ensure_loaded()
        return self._by_id.get(set_id)

    async def icon_path(
        self, set_id: str, icon_name: str
    ) -> AbsolutePath | None:
        await self._ensure_loaded()
        if set_id not in self._by_id:
            return None
        svg = self._root / set_id / ICONS_DIRNAME / f"{icon_name}.svg"
        if not svg.is_file():
            return None
        return AbsolutePath(str(svg.resolve()))

    async def _ensure_loaded(self) -> None:
        """Scan the set tree once, behind the lock."""
        if self._loaded:
            return
        async with self._lock:
            if self._loaded:
                return
            self._load()

    def _load(self) -> None:
        """Read every ``<root>/<set>/set.yaml`` into the in-memory map.

        Raises:
            ProviderError: a ``set.yaml`` is malformed or fails validation.
        """
        rebuilt: dict[str, IconSetCatalogEntry] = {}
        if self._root.is_dir():
            for manifest in sorted(self._root.glob(f"*/{SET_MANIFEST_NAME}")):
                try:
                    raw = yaml.safe_load(manifest.read_text(encoding="utf-8"))
                    entry = IconSetCatalogEntry.model_validate(raw)
                except Exception as exc:
                    raise ProviderError(
                        f"icon set manifest invalid: {manifest}: {exc}"
                    ) from exc
                rebuilt[entry.id] = entry
        self._by_id = rebuilt
        self._loaded = True
        logger.debug(
            "icon set catalog loaded: %d sets from %s",
            len(rebuilt),
            self._root,
        )
