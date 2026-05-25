"""LottieRecolorService — CALL 2: map a preset's regions to palette roles.

The colour-saturated half of resolving a lottie slot, kept separate from
selection so its heavy palette context (every palette key, its value, and
the semantic role descriptions) doesn't bloat the selection prompt.

The LLM is shown the chosen preset's recolourable regions and the run's
full flat palette, and returns a ``region -> palette key`` map. Output
stores only the role NAME per region — the Flutter app resolves the
actual colour at render time against its own live palette, so the
pipeline never bakes a colour value in. The map's keys/values are
contract-checked against the preset's regions and the palette keys inside
the existing structured-output retry loop.
"""

from __future__ import annotations

from pathlib import Path
from string import Template

from schema.lottie_library import LottiePreset
from schema.output.color_palette import ColorPalette
from src.core.run_context import RunContext
from src.modules.lotties.lottie_models import build_recolor_model
from src.shared.interfaces.llm_client import LLMClient

RECOLOR_PROMPT_PATH = (
    Path(__file__).parent / "prompts" / "lottie_recolor_rule.md"
)

# Per-call constant, not config. Haiku: a constrained mapping over a known
# vocabulary, contract-enforced by the closed schema.
LOTTIE_RECOLOR_MODEL = "anthropic/claude-haiku-4-5"


class LottieRecolorService:
    """Runs the one structured recolour call and returns the region->role
    map (role names only, validated against the palette keys)."""

    def __init__(self, llm: LLMClient) -> None:
        self._llm = llm

    async def resolve(
        self,
        run_ctx: RunContext,
        *,
        preset: LottiePreset,
        palette: ColorPalette,
        model: str = LOTTIE_RECOLOR_MODEL,
    ) -> dict[str, str]:
        """Map every region of ``preset`` to a palette key."""
        palette_keys = frozenset(palette.palette.keys())
        response_model = build_recolor_model(
            regions=[r.name for r in preset.recolor_regions],
            palette_keys=palette_keys,
        )
        prompt = self._build_prompt(preset, palette)
        result = await self._llm.complete_structured(
            [{"role": "user", "content": prompt}],
            schema=response_model,
            model=model,
        )
        return dict(result.region_roles)

    @staticmethod
    def _build_prompt(preset: LottiePreset, palette: ColorPalette) -> str:
        """Preset + region list + the full palette vocabulary (keys, values
        and the semantic role descriptions) substituted into the rule."""
        template = RECOLOR_PROMPT_PATH.read_text(encoding="utf-8")
        # Each line names the region and says what that color does, so the
        # LLM maps it to a palette role on purpose, not from the bare layer
        # name.
        regions = "\n".join(
            f"  - {r.name} — {r.description}" for r in preset.recolor_regions
        )
        # Semantic descriptions for the base roles (helps the LLM avoid
        # picking a harsh base colour when a softer derived key fits).
        role_meanings = "\n".join(
            f"  {slot_id}: {color.display_name} — {color.description}"
            for slot_id, color in palette.colors.items()
        )
        # The full flat palette: every selectable key (base + derived +
        # shared surfaces) with its concrete value, so the LLM picks from
        # the real vocabulary and can dodge ugly base tones.
        palette_keys = "\n".join(
            f"  {key}: {value.oklch!s} / {value.hex.root}"
            for key, value in palette.palette.items()
        )
        return Template(template).safe_substitute(
            preset=f"{preset.display_name} — {preset.description}",
            regions=regions,
            role_meanings=role_meanings,
            palette=palette_keys,
        )
