"""LottiePresetLibrary — loads and indexes the global preset catalog.

The Lottie analog of the Google Fonts catalog: a hand-curated set of
animation presets the lottie module selects from. App-agnostic and
global — it does not live under any ``apps/<app_id>/``. Files sit under
``assets/lottie_animations/``; ``index.yaml`` there validates against
``LottieLibrary``.

Built once per run in the registry and shared across every lottie node
(the way ``ComplexityClassifier`` is shared across image nodes), so the
catalog is read and validated a single time.
"""

from __future__ import annotations

from pathlib import Path

import yaml

from schema.lottie_library import LottieLibrary, LottiePreset
from schema.lottie_type import LottieType

# Repo root from ``src/modules/lotties/`` is ``parents[3]``; the global
# library lives at ``assets/lottie_animations/`` beside ``apps/``.
LOTTIE_LIBRARY_ROOT = (
    Path(__file__).resolve().parents[3] / "assets" / "lottie_animations"
)
LOTTIE_INDEX_FILENAME = "index.yaml"


class LottiePresetLibrary:
    """The loaded catalog, indexed by preset id."""

    def __init__(self, presets: list[LottiePreset]) -> None:
        self._by_id: dict[str, LottiePreset] = {p.id: p for p in presets}

    @classmethod
    def load(cls, root: Path = LOTTIE_LIBRARY_ROOT) -> "LottiePresetLibrary":
        """Read ``<root>/index.yaml`` and validate it into the catalog."""
        index = root / LOTTIE_INDEX_FILENAME
        raw = yaml.safe_load(index.read_text(encoding="utf-8"))
        library = LottieLibrary.model_validate(raw)
        return cls(library.presets)

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
