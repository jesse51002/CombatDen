"""LottiePresetLibrary — loads and indexes the global preset catalog.

The Lottie analog of the Google Fonts catalog: a hand-curated set of
animation presets the lottie module selects from. App-agnostic and
global — it does not live under any ``apps/<app_id>/``. Each preset is
its own folder (mirroring an icon set's ``<root>/<set>/set.yaml``)::

    <root>/<preset_id>/config.yaml   # the LottiePreset
    <root>/<preset_id>/<file>.json   # the animation, beside its config

The loader scans the folders and validates each ``config.yaml`` straight
into a ``LottiePreset`` (no list wrapper), the way ``LocalIconSetCatalog``
reads one ``IconSetCatalogEntry`` per ``set.yaml``. ``preset.file`` is the
animation filename **relative to the preset's own folder**; the library
records the resolved absolute json path per id so the bake step can read
it without re-deriving the layout.

Built once per run in the registry and shared across every lottie node
(the way ``ComplexityClassifier`` is shared across image nodes), so the
catalog is read and validated a single time.
"""

from __future__ import annotations

from pathlib import Path

import yaml

from schema.lottie_library import LottiePreset
from schema.lottie_type import LottieType
from schema.primitives import AbsolutePath

# Repo root from ``src/modules/lotties/`` is ``parents[3]``; the global
# library lives at ``assets/lottie_animations/`` beside ``apps/``.
LOTTIE_LIBRARY_ROOT = (
    Path(__file__).resolve().parents[3] / "assets" / "lottie_animations"
)
# One config per preset folder (replaces the old single ``index.yaml``).
LOTTIE_CONFIG_FILENAME = "config.yaml"


class LottiePresetLibrary:
    """The loaded catalog, indexed by preset id, with each preset's
    resolved animation json path (under its own folder)."""

    def __init__(
        self, presets: list[LottiePreset], json_paths: dict[str, Path]
    ) -> None:
        self._by_id: dict[str, LottiePreset] = {p.id: p for p in presets}
        # preset id -> absolute path of its animation json (``<dir>/<file>``).
        self._json_paths = json_paths

    @classmethod
    def load(cls, root: Path = LOTTIE_LIBRARY_ROOT) -> "LottiePresetLibrary":
        """Scan ``<root>/<id>/config.yaml`` and validate each into the
        catalog. Raises ``ValueError`` on a duplicate preset id (two folders
        whose ``config.yaml`` declare the same id)."""
        presets: list[LottiePreset] = []
        json_paths: dict[str, Path] = {}
        if root.is_dir():
            for config in sorted(root.glob(f"*/{LOTTIE_CONFIG_FILENAME}")):
                raw = yaml.safe_load(config.read_text(encoding="utf-8"))
                preset = LottiePreset.model_validate(raw)
                if preset.id in json_paths:
                    raise ValueError(
                        f"duplicate lottie preset id {preset.id!r} "
                        f"(folder {config.parent.name!r})"
                    )
                presets.append(preset)
                json_paths[preset.id] = (config.parent / preset.file).resolve()
        return cls(presets, json_paths)

    def candidates(self, animation_type: LottieType) -> list[LottiePreset]:
        """Every preset carrying ``animation_type`` as one of its tags
        (a preset can match more than one type)."""
        return [
            preset
            for preset in self._by_id.values()
            if animation_type in preset.types
        ]

    def get(self, preset_id: str) -> LottiePreset:
        """The preset with this id (raises ``KeyError`` if unknown)."""
        return self._by_id[preset_id]

    def json_path(self, preset_id: str) -> AbsolutePath:
        """Absolute path of one preset's animation json (under its own
        folder). Raises ``KeyError`` for an unknown id."""
        return AbsolutePath(str(self._json_paths[preset_id]))
