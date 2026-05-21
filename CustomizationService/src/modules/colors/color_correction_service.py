"""ColorCorrectionService — the post-LLM colour clamp.

One job: pull the background colour's lightness into the safe band so
the client always has elevation headroom for cards and popups (README
TODO #1). This is the one deliberate exception to the raise-and-re-ask
discipline — the LLM's strict contract (in ``color_models``) does NOT
check background lightness, so a near-extreme answer is corrected here
rather than re-asked. In-band input is returned unchanged; the clamp
is idempotent.

The strict sanity contract (chroma + text-L + WCAG AA contrast) lives
on the LLM response model's ``model_validator`` in ``color_models`` —
that's what model_validator is for. It is NOT this service's
responsibility; this file is just the clamp.
"""

from __future__ import annotations

from schema import OklchColor
from src.modules.colors.color_models import LLMPalette

# Background lightness BAND, by mode — two-sided on purpose. The MobileApp
# client builds elevated surfaces by compositing a translucent veil over
# the resolved background; a background flush against an extreme leaves
# no tonal room for elevation to read (README TODO #1). These bounds are
# enforced by the clamp inside ``apply`` — the contract in
# ``color_models`` does NOT raise on background lightness, so a
# near-extreme answer is silently corrected rather than re-asked.
DARK_MODE_BG_L_MIN = 0.08
DARK_MODE_BG_L_MAX = 0.30
LIGHT_MODE_BG_L_MIN = 0.86
LIGHT_MODE_BG_L_MAX = 0.90


class ColorCorrectionService:
    """Applies deterministic post-LLM corrections to a ``LLMPalette``.

    Today that's just the background lightness clamp; future corrections
    (e.g. text/bg luminance pair guarantees) plug in here without
    touching the node or the scheme service. Stateless; one instance is
    fine for the whole run.
    """

    def apply(self, schema: LLMPalette) -> LLMPalette:
        """Return a new ``LLMPalette`` with corrections applied.

        Looks up the background-role slot, clamps its L into the safe
        band, and returns a copy of the schema with that slot's OKLCH
        replaced. Other slots are unchanged. In-band background is an
        identity rewrite — the clamp is idempotent.
        """
        bg_id = schema.background_id
        old_bg = schema.colors[bg_id]
        new_bg_oklch = self._clamp_bg_lightness(
            old_bg.oklch, dark_mode=schema.dark_mode
        )
        if new_bg_oklch is old_bg.oklch:
            return schema  # clamp was idempotent — no rewrite needed
        new_colors = dict(schema.colors)
        new_colors[bg_id] = old_bg.model_copy(update={"oklch": new_bg_oklch})
        return schema.model_copy(update={"colors": new_colors})

    @staticmethod
    def _clamp_bg_lightness(
        color: OklchColor, *, dark_mode: bool
    ) -> OklchColor:
        """Pull a background colour's L into the safe band — deterministic,
        idempotent. Only L is rewritten; C / H / alpha are preserved
        structurally via ``model_copy(update=...)``. In-band input is
        returned unchanged (same object).
        """
        lo, hi = (
            (DARK_MODE_BG_L_MIN, DARK_MODE_BG_L_MAX)
            if dark_mode
            else (LIGHT_MODE_BG_L_MIN, LIGHT_MODE_BG_L_MAX)
        )
        clamped = min(hi, max(lo, color.l))
        if clamped == color.l:
            return color
        return color.model_copy(update={"l": clamped})
