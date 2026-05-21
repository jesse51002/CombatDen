"""ColorDerivationService — expand ONE colour into its full ``ColorOutput``.

Atomic by design: the public method ``expand`` takes a single resolved
slot and produces that colour's base ``ColorValue`` plus its seven
derivations (``second`` / ``third`` alpha tints, ``card`` / ``popup``
surfaces, ``dark`` / ``light`` lightness shifts, and ``regular_text`` —
the readable colour for text painted ON this colour). It does NOT loop the
palette, compute the shared surfaces, or assemble the flat
recommendation dict — the node orchestrates iteration, and
``ColorSurfaceService`` owns the run-wide surfaces (passed in here so
the background + text slots can reuse them).

The format conversion + alpha + composite ops live on the primitives
(``ColorValue.from_oklch``, ``OklchColor.with_alpha`` /
``composite_over``); this service only holds the per-colour-specific
formulas (the mode-aware dark/light lightness shifts and the chromatic
card alpha). Every helper is a ``@staticmethod`` — no loose functions.
"""

from __future__ import annotations

from schema import ColorRole, OklchColor
from schema.output.color_output import ColorOutput
from schema.output.color_value import ColorValue
from schema.output.derivations import Derivations
from src.modules.colors.color_models import MIN_CONTRAST_AA, LLMSlotResponse
from src.modules.colors.color_surface_service import SharedSurfaces

# Alpha tints — lifted verbatim from MobileApp/lib/core/design_constants.dart
# (text2nd at 0.75, text3rd at 0.50). Every slot gains these two for
# consistency; the MobileApp's per-slot ad-hoc tints all collapse to them.
SECOND_ALPHA = 0.75
THIRD_ALPHA = 0.50

# Mode-aware dark/light invariants:
#   dark.l  <  canvas.l - DARK_MIN_GAP
#   light.l >  canvas.l + LIGHT_MIN_GAP
DARK_MIN_GAP = 0.06
LIGHT_MIN_GAP = 0.10
L_FLOOR = 0.02
L_CEIL = 0.98

# darkPrimary multiplier from design_constants.dart:40 ("shift toward
# black"); mirrored for `light` as (1 - L) * LIGHT_MULT_TOWARD_WHITE.
DARK_MULT = 0.42
LIGHT_MULT_TOWARD_WHITE = 0.58


class ColorDerivationService:
    """Expands one colour into its full ``ColorOutput``. Atomic and
    stateless; the node calls it once per slot."""

    def expand(
        self,
        slot: LLMSlotResponse,
        *,
        role: ColorRole | None,
        canvas: OklchColor,
        text: OklchColor,
        dark_mode: bool,
        surfaces: SharedSurfaces,
    ) -> ColorOutput:
        """One resolved slot → its ``ColorOutput`` (base value + the seven
        derivations). ``surfaces`` supplies the shared card/popup the
        background + text slots reuse instead of tinting their own;
        ``canvas`` / ``text`` are the resolved background + body-text
        colours, used to pick the slot's ``regular_text`` foreground."""
        return ColorOutput(
            color=ColorValue.from_oklch(slot.oklch),
            display_name=slot.display_name,
            description=slot.description,
            derivations=self._derive(
                slot.oklch,
                role=role,
                canvas=canvas,
                text=text,
                dark_mode=dark_mode,
                surfaces=surfaces,
            ),
        )

    @classmethod
    def _derive(
        cls,
        base: OklchColor,
        *,
        role: ColorRole | None,
        canvas: OklchColor,
        text: OklchColor,
        dark_mode: bool,
        surfaces: SharedSurfaces,
    ) -> Derivations:
        # second / third: alpha tints (L/C/H preserved structurally).
        second = base.with_alpha(SECOND_ALPHA)
        third = base.with_alpha(THIRD_ALPHA)

        # dark / light: lightness shifts (C/H preserved structurally).
        dark = base.model_copy(
            update={"l": cls._dark_l(base.l, canvas.l), "alpha": None}
        )
        light = base.model_copy(
            update={"l": cls._light_l(base.l, canvas.l), "alpha": None}
        )

        # card / popup: shared for bg/text; chromatic for the rest.
        if role in (ColorRole.BACKGROUND, ColorRole.TEXT):
            card = surfaces.card
            popup = surfaces.popup
        else:
            card_oklch = base.with_alpha(
                cls._card_alpha(canvas.l, dark_mode=dark_mode)
            )
            card = ColorValue.from_oklch(card_oklch)
            popup = ColorValue.from_oklch(card_oklch.composite_over(canvas))

        # regular_text: a readable foreground for text painted ON this colour.
        regular_text = cls._regular_text(base, text=text, canvas=canvas)

        return Derivations(
            second=ColorValue.from_oklch(second),
            third=ColorValue.from_oklch(third),
            card=card,
            popup=popup,
            dark=ColorValue.from_oklch(dark),
            light=ColorValue.from_oklch(light),
            regular_text=ColorValue.from_oklch(regular_text),
        )

    @staticmethod
    def _regular_text(
        base: OklchColor, *, text: OklchColor, canvas: OklchColor
    ) -> OklchColor:
        """Readable foreground for text painted ON ``base``: the body
        ``text`` colour if it clears WCAG AA against the fill, else
        whichever of {text, canvas} contrasts better. ``canvas`` is the
        background slot — and text↔background are already AA by contract,
        so a fill near either pole always has a usable winner. Per-colour
        because a fill can sit closer to the canvas than to the text."""
        text_ratio = base.contrast(text)
        if text_ratio >= MIN_CONTRAST_AA:
            return text
        return text if text_ratio >= base.contrast(canvas) else canvas

    @staticmethod
    def _card_alpha(canvas_L: float, *, dark_mode: bool) -> float:
        """Per-chromatic-slot card alpha. Larger than the white/black
        veil because tinted veils read weaker than neutral ones at the
        same alpha."""
        if dark_mode:
            return 0.10 + 0.20 * canvas_L
        return 0.08 + 0.10 * (1.0 - canvas_L)

    @staticmethod
    def _dark_l(base_L: float, canvas_L: float) -> float:
        """``dark`` lightness. Always lands below canvas L by ≥ DARK_MIN_GAP."""
        ceiling = canvas_L - DARK_MIN_GAP
        return max(L_FLOOR, min(base_L * DARK_MULT, ceiling))

    @staticmethod
    def _light_l(base_L: float, canvas_L: float) -> float:
        """``light`` lightness. Always lands above canvas L by ≥ LIGHT_MIN_GAP."""
        floor = canvas_L + LIGHT_MIN_GAP
        shifted = base_L + (1.0 - base_L) * LIGHT_MULT_TOWARD_WHITE
        return min(L_CEIL, max(shifted, floor))
