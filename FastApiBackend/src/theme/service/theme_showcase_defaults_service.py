"""ThemeShowcaseDefaultsService — category-keyed demo showcase cards.

Serves the standalone theme browser's demo class/reward cards from a bundled
repo YAML file. There is NO database here: the cards are static, category-keyed
sample content shown when no real gym is selected (the public theme browser has
no login). The file is parsed + validated into ``ShowcaseDefaults`` once, then
cached on the instance for the process lifetime.
"""

from __future__ import annotations

import asyncio
from pathlib import Path

import yaml
from pydantic import ValidationError

from src.theme import SHOWCASE_DEFAULTS_FILE
from src.theme.schema.theme_schema import ShowcaseCategory, ShowcaseDefaults


class ThemeShowcaseDefaultsService:
    """Read-only access to the bundled, category-keyed showcase demo cards."""

    def __init__(
        self, defaults_file: Path = SHOWCASE_DEFAULTS_FILE
    ) -> None:
        self._defaults_file = defaults_file
        self._cache: ShowcaseDefaults | None = None

    async def load_defaults(self) -> ShowcaseDefaults:
        """The category-keyed demo class/reward cards. Parsed + validated on
        the first call (off the event loop), then cached on the instance for
        every subsequent read."""
        if self._cache is None:
            self._cache = await asyncio.to_thread(self._load)
        return self._cache

    def _load(self) -> ShowcaseDefaults:
        """Read, parse, and validate the YAML into ``ShowcaseDefaults``. Raises
        ``ValueError`` with a clear message on any read/parse/validation
        failure or an incomplete category set."""
        try:
            raw = self._defaults_file.read_text(encoding="utf-8")
            data = yaml.safe_load(raw)
            defaults = ShowcaseDefaults.model_validate(data)
        except (OSError, yaml.YAMLError, ValidationError) as exc:
            raise ValueError(
                f"Invalid showcase defaults file "
                f"{self._defaults_file}: {exc}"
            ) from exc
        self._validate_complete(defaults)
        return defaults

    @staticmethod
    def _validate_complete(defaults: ShowcaseDefaults) -> None:
        """Every ``ShowcaseCategory`` must be present with a non-empty class
        and reward list — the browser has no fallback for a missing or empty
        category."""
        for category in ShowcaseCategory:
            group = defaults.categories.get(category)
            if group is None:
                raise ValueError(
                    f"Showcase defaults missing category: {category.value}"
                )
            if not group.classes or not group.rewards:
                raise ValueError(
                    f"Showcase defaults category {category.value} must have "
                    "at least one class and one reward"
                )
