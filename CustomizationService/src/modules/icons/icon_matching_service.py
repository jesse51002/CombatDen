"""IconMatchingService — matches every icon slot to an icon in the chosen
set (one LLM call), then copies each matched SVG into the run dir.

Call 2 of the icon module's three. Owns its whole half of the resolution:
the matching call AND the copy of every matched icon's SVG into the run's
``icons/`` dir, returning the resolved matched ``IconOutput``s plus the
slots that found no honest match (which the generation service handles).
The set-membership contract rides the existing ``complete_structured``
retry loop via the per-request model's after-validator (see
``build_icon_match_model``).

A ``null`` pick is the honest "no icon in this set fits" answer — a wrong
icon is worse than a generated one. A matched slot whose SVG can't be
copied is dropped fail-soft (logged); the rest still resolve.
"""

from __future__ import annotations

import logging
import shutil
from pathlib import Path
from string import Template

from schema import IconOutput, IconSlot
from src.core.run_context import RunContext
from src.modules.icons.icon_models import build_icon_match_model
from src.shared.interfaces.icon_set_catalog import (
    IconSetCatalog,
    IconSetCatalogEntry,
)
from src.shared.interfaces.llm_client import LLMClient

logger = logging.getLogger(__name__)

ICON_MATCH_PROMPT_PATH = (
    Path(__file__).parent / "prompts" / "icon_matching_rule.md"
)

# Model for the matching call. A per-call constant, not config: Haiku is
# plenty — the closed schema + set-membership contract constrain it.
ICON_MATCH_MODEL = "anthropic/claude-haiku-4-5"


class IconMatchingService:
    """Matches every icon slot within the chosen set and copies the
    matched SVGs into the run dir."""

    def __init__(self, llm: LLMClient, catalog: IconSetCatalog) -> None:
        self._llm = llm
        self._catalog = catalog

    async def match(
        self,
        run_ctx: RunContext,
        chosen: IconSetCatalogEntry,
        *,
        model: str = ICON_MATCH_MODEL,
    ) -> tuple[dict[str, IconOutput], list[IconSlot]]:
        """Run the matching call, copy each matched SVG into the run dir.

        Returns ``(matched, unmatched)``: the resolved ``IconOutput`` per
        slot matched within ``chosen`` (its SVG copied into the run dir),
        and the slots nothing in the set honestly fit (for the caller to
        generate). A matched slot whose SVG can't be copied is dropped.
        """
        slots = list(run_ctx.app.icons)
        response_model = build_icon_match_model(
            [s.id for s in slots], icon_names=frozenset(chosen.icons)
        )
        messages = [
            {"role": "user", "content": self._build_prompt(run_ctx, chosen)}
        ]
        resolved = await self._llm.complete_structured(
            messages, schema=response_model, model=model
        )

        matched: dict[str, IconOutput] = {}
        unmatched: list[IconSlot] = []
        for slot in slots:
            icon_name = getattr(resolved, slot.id).icon
            if icon_name is None:
                unmatched.append(slot)
                continue
            out = await self._copy_matched(run_ctx, slot.id, chosen, icon_name)
            if out is not None:
                matched[slot.id] = out
        return matched, unmatched

    async def _copy_matched(
        self,
        run_ctx: RunContext,
        slot_id: str,
        chosen: IconSetCatalogEntry,
        icon_name: str,
    ) -> IconOutput | None:
        """Copy one matched icon's SVG into the run dir; build its output.

        Returns ``None`` (and logs) if the set's SVG is missing or the
        copy fails — the slot is dropped, never aborting the others."""
        dest = Path(str(run_ctx.icon_path(slot_id)))
        try:
            src = await self._catalog.icon_path(chosen.id, icon_name)
            if src is None:
                raise FileNotFoundError(
                    f"matched icon {icon_name!r} has no SVG in set "
                    f"{chosen.id!r}"
                )
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(str(src), dest)
        except Exception as exc:  # noqa: BLE001 — fail soft per slot
            logger.warning(
                "icon slot %s matched %r but could not be copied (%s); "
                "dropping it",
                slot_id,
                icon_name,
                exc,
            )
            return None
        return IconOutput(
            path=run_ctx.icon_path(slot_id),
            icon_set=chosen.id,
            icon_set_name=chosen.name,
            icon_key=slot_id,
        )

    @staticmethod
    def _build_prompt(
        run_ctx: RunContext, chosen: IconSetCatalogEntry
    ) -> str:
        """Rule + brand brief + icon-slot inventory + the chosen set's
        vibe and icon vocabulary, substituted into the one ``.md``
        template."""
        template = ICON_MATCH_PROMPT_PATH.read_text(encoding="utf-8")
        design = run_ctx.cust.design_direction
        inventory = "\n".join(
            f"- {slot.id}: {slot.description}" for slot in run_ctx.app.icons
        )
        icons = ", ".join(chosen.icons)
        return Template(template).safe_substitute(
            name=design.name,
            short=design.short_desc,
            long=design.long_desc,
            slots=inventory,
            set_name=chosen.name,
            set_vibe=chosen.vibe.strip(),
            icons=icons,
        )
