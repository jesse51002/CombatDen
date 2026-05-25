"""IconSetSelectionService — the one structured LLM call that picks the
best-fit curated icon set for the brand.

Call 1 of the icon module's three. The LLM sees the brand brief and every
curated set's id / name / vibe, and returns the single set id whose style
best matches the brand. The known-set-id contract rides the existing
``complete_structured`` retry loop via the per-request model's
after-validator (see ``build_icon_set_selection_model``).

Returns the chosen ``IconSetCatalogEntry`` (looked up from the catalog),
which the matching call then constrains itself to.
"""

from __future__ import annotations

from pathlib import Path
from string import Template

from src.core.errors import ProviderError
from src.core.run_context import RunContext
from src.modules.icons.icon_models import build_icon_set_selection_model
from src.shared.interfaces.icon_set_catalog import (
    IconSetCatalog,
    IconSetCatalogEntry,
)
from src.shared.interfaces.llm_client import LLMClient

ICON_SET_PROMPT_PATH = (
    Path(__file__).parent / "prompts" / "icon_set_selection_rule.md"
)

# Model for the set-selection call. A per-call constant, not config:
# Haiku is plenty — the closed schema + known-set-id contract constrain
# the answer. Override via ``select(model=...)`` in dev.
ICON_SET_MODEL = "anthropic/claude-haiku-4-5"


class IconSetSelectionService:
    """Builds the selection prompt and runs the one structured call that
    picks the best-fit icon set, then returns its catalog entry."""

    def __init__(self, llm: LLMClient, catalog: IconSetCatalog) -> None:
        self._llm = llm
        self._catalog = catalog

    async def select(
        self, run_ctx: RunContext, *, model: str = ICON_SET_MODEL
    ) -> IconSetCatalogEntry:
        """Run the set-selection call; return the chosen set's entry.

        Raises:
            ProviderError: the catalog has no sets, or the chosen id can't
                be looked up (structurally unreachable — the validator
                already enforced membership).
        """
        sets = await self._catalog.sets()
        if not sets:
            raise ProviderError(
                "icon set catalog is empty — no set to select from"
            )
        set_ids = frozenset(s.id for s in sets)
        response_model = build_icon_set_selection_model(set_ids)
        messages = [
            {"role": "user", "content": self._build_prompt(run_ctx, sets)}
        ]
        resolved = await self._llm.complete_structured(
            messages, schema=response_model, model=model
        )
        chosen = await self._catalog.lookup(resolved.icon_set)
        if chosen is None:
            raise ProviderError(
                f"icon set lookup miss after validation pass: "
                f"{resolved.icon_set!r}"
            )
        return chosen

    @staticmethod
    def _build_prompt(
        run_ctx: RunContext, sets: list[IconSetCatalogEntry]
    ) -> str:
        """Rule + brand brief + the catalog of sets (id, name, vibe),
        substituted into the one ``.md`` template."""
        template = ICON_SET_PROMPT_PATH.read_text(encoding="utf-8")
        design = run_ctx.cust.design_direction
        catalog = "\n\n".join(
            f"- id: {s.id}\n  name: {s.name}\n  vibe: {s.vibe.strip()}"
            for s in sets
        )
        return Template(template).safe_substitute(
            name=design.name,
            short=design.short_desc,
            long=design.long_desc,
            sets=catalog,
        )
