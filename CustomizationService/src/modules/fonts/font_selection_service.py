"""FontSelectionService — owns the one structured LLM call that picks
a Google Font for every font slot the app declares.

The LLM is asked for the family plus prose per slot; the Google Fonts
membership contract rides the existing ``complete_structured`` retry
loop via the ``model_validator(mode="after")`` on the per-request
response model. The validator is sync, so the catalog snapshot is
pre-awaited and fed into the model factory once. Failures (any picked
family the live catalog doesn't recognise) re-ride the same loop —
zero new retry code.

The service returns a fully resolved ``FontSet`` (each slot's
``FontOutput``, with the ``category`` field looked up from the catalog
entry rather than asked of the LLM). This is the colour module's three-
service composition collapsed to one: fonts have no math step, so the
selection IS the resolution.
"""

from __future__ import annotations

from pathlib import Path
from string import Template

from schema import FontOutput, FontSet
from src.core.errors import ProviderError
from src.core.run_context import RunContext
from src.modules.fonts.font_models import (
    LLMFontResponse,
    build_font_response_model,
)
from src.shared.interfaces.google_fonts_catalog import GoogleFontsCatalog
from src.shared.interfaces.llm_client import LLMClient

FONT_PROMPT_PATH = Path(__file__).parent / "prompts" / "font_selection_rule.md"

# Model for the one font-selection call. A per-call constant, not config:
# the model is a property of this call. Override via ``resolve(model=...)``
# in dev (bake-off scripts under ``scripts/``); production uses this default.
# Haiku is plenty for the task — the structured schema + catalog
# membership contract do the heavy constraining.
FONT_MODEL = "anthropic/claude-haiku-4-5"


class FontSelectionService:
    """Builds the LLM prompt and runs the one structured call that
    resolves every font slot, then lifts each pick into a ``FontOutput``
    via the catalog (which supplies the canonical family + category)."""

    def __init__(
        self, llm: LLMClient, catalog: GoogleFontsCatalog
    ) -> None:
        self._llm = llm
        self._catalog = catalog

    async def resolve(
        self, run_ctx: RunContext, *, model: str = FONT_MODEL
    ) -> FontSet:
        """Run the font LLM call; return the resolved ``FontSet``.

        The per-request closed model is built per call so the LLM sees an
        explicit, required field for every font slot id in this run's
        app (Anthropic strict structured output rejects open maps). The
        Google-Fonts membership contract is the
        ``model_validator(mode="after")`` on that model — failures
        re-ride the existing structured-output retry loop in
        ``LiteLLMClient``, this function returns only after the
        contract is clean.
        """
        slot_ids = [slot.id for slot in run_ctx.app.fonts]
        known_families = await self._catalog.families()
        response_model = build_font_response_model(
            slot_ids, known_families=known_families
        )
        messages = [
            {"role": "user", "content": self._build_prompt(run_ctx)}
        ]
        resolved = await self._llm.complete_structured(
            messages, schema=response_model, model=model
        )
        fonts: dict[str, FontOutput] = {}
        for slot_id in slot_ids:
            pick: LLMFontResponse = getattr(resolved, slot_id)
            entry = await self._catalog.lookup(pick.family)
            if entry is None:
                # The model_validator already enforced membership, so
                # this is structurally unreachable. Defensive: treat as
                # a provider fault if it ever fires.
                raise ProviderError(
                    f"Google Fonts lookup miss after validation pass: "
                    f"{pick.family!r}"
                )
            fonts[slot_id] = FontOutput(
                family=entry.family,
                category=entry.category,
                display_name=pick.display_name,
                description=pick.description,
            )
        return FontSet(fonts=fonts)

    @staticmethod
    def _build_prompt(run_ctx: RunContext) -> str:
        """Rule + brand brief + font-slot inventory, substituted into the
        one ``.md`` template (``safe_substitute`` tolerates a stray ``$``)."""
        template = FONT_PROMPT_PATH.read_text(encoding="utf-8")
        design = run_ctx.cust.design_direction
        inventory = "\n".join(
            f"- {slot.id}: {slot.description}"
            for slot in run_ctx.app.fonts
        )
        return Template(template).safe_substitute(
            name=design.name,
            short=design.short_desc,
            long=design.long_desc,
            slots=inventory,
        )
