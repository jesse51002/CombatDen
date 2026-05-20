"""ColorNode — the colour graph node: resolve every colour slot in one call.

The DAG root: it has no dependencies and every image node depends on it.
``run()`` resolves the whole palette in one structured LLM call (atomic —
the executor owns iteration, this node owns the single palette call).
"""

from __future__ import annotations

import logging
from pathlib import Path
from string import Template

from schema import ColorMode, ColorPalette, ColorRole
from src.core.run_context import RunContext
from src.modules.base import DependencyKind, Node
from src.modules.colors.color_models import build_color_response_model
from src.modules.colors.color_validation import clamp_bg_lightness
from src.shared.interfaces.llm_client import LLMClient

logger = logging.getLogger(__name__)

COLOR_PROMPT_PATH = Path(__file__).parent / "prompts" / "color_palette_rule.md"

# Model for the one colour-palette call. A per-call constant, not config:
# the model is a property of this call. Override `run(model=...)` in dev
# (bake-off scripts under `scripts/`); production uses this default.
COLOR_MODEL = "anthropic/claude-sonnet-4-6"


class ColorNode(Node):
    """The colour node. ``run() -> ColorPalette``. No dependencies."""

    def __init__(self, run_ctx: RunContext, *, llm: LLMClient) -> None:
        super().__init__(
            run_ctx, key=DependencyKind.COLOR.value, deps=frozenset()
        )
        self._llm = llm

    async def run(self, *, model: str = COLOR_MODEL) -> ColorPalette:
        """Resolve every colour slot; return the ``ColorPalette`` model.

        The wire schema is a per-request closed model so Pydantic validates
        the response accurately; the result is flattened back into the
        ``ColorPalette`` map. ``model`` defaults to the module constant;
        override it in dev to compare models. Takes no positional inputs —
        the root has no dependencies, so ``inputs`` is unused.
        """
        messages = [{"role": "user", "content": self._build_prompt()}]
        slot_ids = [slot.id for slot in self._run_ctx.app.colors]
        # roles + mode come from app.yaml / customization.yaml (never the
        # LLM); they drive the deterministic contract on the wire model.
        roles = {slot.id: slot.role for slot in self._run_ctx.app.colors}
        mode = self._run_ctx.cust.colors_direction.mode
        response_model = build_color_response_model(
            slot_ids, roles=roles, dark_mode=mode is ColorMode.DARK
        )
        resolved = await self._llm.complete_structured(
            messages,
            schema=response_model,
            model=model,
        )
        colors = {
            slot_id: getattr(resolved, slot_id) for slot_id in slot_ids
        }
        # The colour contract no longer raises on background lightness:
        # the background band is enforced here, deterministically, so a
        # near-extreme answer is corrected (not re-asked) and the client
        # always has elevation headroom. See clamp_bg_lightness. AppFormat
        # guarantees exactly one background-role slot, so next() is safe.
        bg_id = next(
            sid for sid, r in roles.items() if r is ColorRole.BACKGROUND
        )
        colors[bg_id] = clamp_bg_lightness(
            colors[bg_id], dark_mode=mode is ColorMode.DARK
        )
        return ColorPalette(mode=mode, colors=colors)

    def _build_prompt(self) -> str:
        """Rule + brand brief + slot inventory, substituted into the one
        ``.md`` template (``safe_substitute`` tolerates a stray ``$``)."""
        template = COLOR_PROMPT_PATH.read_text(encoding="utf-8")
        design = self._run_ctx.cust.design_direction
        colors = self._run_ctx.cust.colors_direction
        inventory = "\n".join(
            f"- {slot.id}: {slot.description}" for slot in self._run_ctx.app.colors
        )
        return Template(template).safe_substitute(
            name=design.name,
            short=design.short_desc,
            long=design.long_desc,
            colour_direction=colors.description,
            dark_mode=colors.mode is ColorMode.DARK,
            slots=inventory,
        )
