"""ColorSurfaceService — the run-wide "one-time" surfaces of a palette.

Three surfaces, computed once per run from the resolved canvas + text:

- ``card`` — the translucent elevation veil over the canvas (white in
  dark mode, near-black in light mode).
- ``popup`` — the opaque modal surface (the card composited onto the
  canvas so content can't bleed through).
- ``divider`` — the hairline separator, keyed to the text colour with
  an auto-contrast alpha.

These are NOT per-colour — they belong to the palette as a whole, so
they live in their own service rather than being recomputed inside the
atomic per-colour derivation. The derivation service consumes ``card`` /
``popup`` for the background + text slots (those slots reuse the shared
surfaces rather than tinting their own).

The alpha formulas are lifted from MobileApp/lib/core/design_constants.dart
(the dark-mode card alpha and the divider alpha verbatim; the light-mode
card alpha is a corrected mirror — the Dart formula collapses to
whiter-than-white over a near-white canvas).
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict

from schema import OklchColor
from schema.output.color_value import ColorValue


class SharedSurfaces(BaseModel):
    """The three run-wide surfaces, each in every colour format."""

    model_config = ConfigDict(extra="forbid")

    card: ColorValue
    popup: ColorValue
    divider: ColorValue


class ColorSurfaceService:
    """Computes the one-time shared surfaces for a palette. Stateless;
    one instance covers a whole run. Every helper is a ``@staticmethod``
    on this class — no loose functions in the module.
    """

    def compute(
        self, *, canvas: OklchColor, text: OklchColor, dark_mode: bool
    ) -> SharedSurfaces:
        """The shared ``card`` / ``popup`` / ``divider`` for one run."""
        card_oklch = self._card_oklch(canvas, dark_mode=dark_mode)
        return SharedSurfaces(
            card=ColorValue.from_oklch(card_oklch),
            popup=ColorValue.from_oklch(card_oklch.composite_over(canvas)),
            divider=ColorValue.from_oklch(
                text.with_alpha(self._divider_alpha(canvas.l))
            ),
        )

    @staticmethod
    def _card_alpha(canvas_L: float, *, dark_mode: bool) -> float:
        """Dark mode: the Dart elevation alpha (design_constants.dart:71-74).
        Light mode: a fresh mirror — a dark veil over a light canvas;
        Dart's formula collapses to whiter-than-white over a near-white
        canvas, which is the bug this rewrite fixes."""
        if dark_mode:
            return 0.06 + 0.5 * (canvas_L / 0.9)
        return 0.04 + 0.10 * (1.0 - canvas_L)

    @classmethod
    def _card_oklch(cls, canvas: OklchColor, *, dark_mode: bool) -> OklchColor:
        """The translucent neutral veil over the canvas — white in dark
        mode, near-black in light mode. Chroma 0: reads as elevation, not
        as a tint."""
        veil_l = 0.98 if dark_mode else 0.08
        alpha = cls._card_alpha(canvas.l, dark_mode=dark_mode)
        return OklchColor(l=veil_l, c=0.0, h=0.0, alpha=alpha)

    @staticmethod
    def _divider_alpha(canvas_L: float) -> float:
        """Auto-contrast hairline alpha keyed to the canvas lightness
        (lifted from design_constants.dart:150-155)."""
        return min(0.22, max(0.10, 0.10 + 0.10 * canvas_L))
