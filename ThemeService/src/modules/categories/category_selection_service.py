"""CategorySelectionService — the one structured LLM call that files a run
into one of the app's declared ``categories``.

The LLM sees the design name + the brand brief and the app's closed bucket
list, and returns the single best-fit value. The known-value contract rides
the existing ``complete_structured`` retry loop via the per-request model's
after-validator (see ``build_category_selection_model``) — a pick outside the
vocabulary is re-asked, never written.

App-agnostic by construction: the buckets are read off ``run_ctx.app.categories``
at call time and never appear in Python. An app that declares none never gets
this node built (the registry skips it), so this service is only ever reached
with a non-empty vocabulary.
"""

from __future__ import annotations

from pathlib import Path
from string import Template

from src.core.errors import ProviderError
from src.core.run_context import RunContext
from src.modules.categories.category_models import (
    CategoryOutput,
    build_category_selection_model,
)
from src.shared.interfaces.llm_client import LLMClient

CATEGORY_PROMPT_PATH = (
    Path(__file__).parent / "prompts" / "category_selection.md"
)

# Model for the classification call. A per-call constant, not config: the
# model is a property of this call. Override via ``resolve(model=...)`` in
# dev; production uses this default. Haiku is plenty — this is a closed
# single-label pick over a short brief, constrained by the closed schema and
# the vocabulary validator. Matches the other classify-shaped calls in the
# package (icon set selection, text generation).
CATEGORY_MODEL = "anthropic/claude-haiku-4-5"


class CategorySelectionService:
    """Builds the classification prompt and runs the one structured call
    that picks this run's category from the app's declared vocabulary."""

    def __init__(self, llm: LLMClient) -> None:
        self._llm = llm

    async def resolve(
        self, run_ctx: RunContext, *, model: str = CATEGORY_MODEL
    ) -> CategoryOutput:
        """Run the classification call; return the chosen bucket.

        Raises:
            ProviderError: the app declares no categories, so there is no
                vocabulary to classify against. Structurally unreachable via
                the registry (which skips the node entirely in that case);
                this is defense-in-depth for a direct caller.
        """
        categories = run_ctx.app.categories
        if not categories:
            raise ProviderError(
                "app declares no categories — nothing to classify against"
            )
        response_model = build_category_selection_model(frozenset(categories))
        messages = [
            {
                "role": "user",
                "content": self._build_prompt(run_ctx, categories),
            }
        ]
        resolved = await self._llm.complete_structured(
            messages, schema=response_model, model=model
        )
        return CategoryOutput(
            value=resolved.category, reason=resolved.reason
        )

    @staticmethod
    def _build_prompt(run_ctx: RunContext, categories: list[str]) -> str:
        """Rule + design name + brand brief + the app's bucket list,
        substituted into the one ``.md`` template (``safe_substitute``
        tolerates a stray ``$``). The run's steering note is appended under
        the buckets, so ``regen --slot category --spec "…"`` can correct a
        misfile in words."""
        template = CATEGORY_PROMPT_PATH.read_text(encoding="utf-8")
        design = run_ctx.cust.design_direction
        note = run_ctx.overwrite_specs.prompt_note()
        return Template(template).safe_substitute(
            name=design.name,
            short=design.short_desc,
            long=design.long_desc,
            colors=run_ctx.cust.colors_direction.description,
            categories="\n".join(f"- {c}" for c in categories),
            note=f"\n{note}" if note else "",
        )
