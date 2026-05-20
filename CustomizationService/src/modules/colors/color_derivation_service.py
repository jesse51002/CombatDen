"""ColorDerivationService — turns a corrected ``PaletteSchema`` into the
final ``ColorPalette`` the rest of the pipeline + clients consume.

Owns three jobs:

- **Format expansion.** For every base OKLCH the LLM picked, project it
  into the four wire formats (oklch, hsl, rgb, hex) via coloraide and
  bundle them into a ``ColorValue``.
- **Six per-slot derivations** — ``second`` / ``third`` (alpha tints),
  ``card`` / ``popup`` (translucent + opaque surfaces, mode-aware),
  ``dark`` / ``light`` (lightness shifts clamped against the canvas).
  Bundled into a typed ``Derivations`` model per slot.
- **Flat recommendation palette** — every per-slot derivation flattened
  as ``<slot>_<deriv>`` plus shared ``card`` / ``popup`` / ``divider``
  plus the base slot ids; base slots LAST so collisions fall to the
  original (the "no original gets overwritten" invariant).

Coloraide owns every actual conversion, composition and gamut fit; this
file is the pipeline-shaped wiring on top. Every helper is a
``@staticmethod`` on the service — no loose functions in the module.
"""

from __future__ import annotations

from coloraide import Color

from schema import (
    ColorMode,
    ColorPalette,
    ColorRole,
    HexColor,
    HslColor,
    OklchColor,
    RgbColor,
)
from schema.output.color_output import ColorOutput
from schema.output.color_value import ColorValue
from schema.output.derivations import Derivations
from src.modules.colors.color_models import PaletteSchema

# Alpha tints — lifted verbatim from MobileApp/lib/core/design_constants.dart
# (text2nd at 0.75, text3rd at 0.50). Every slot gains these two for
# consistency; the MobileApp's per-slot ad-hoc tints all collapse to them.
SECOND_ALPHA = 0.75
THIRD_ALPHA = 0.50

# Mode-aware dark/light invariants:
#   _dark.l  <  canvas.l - DARK_MIN_GAP
#   _light.l >  canvas.l + LIGHT_MIN_GAP
DARK_MIN_GAP = 0.06
LIGHT_MIN_GAP = 0.10
L_FLOOR = 0.02
L_CEIL = 0.98

# darkPrimary multiplier from design_constants.dart:40 ("shift toward
# black"); mirrored for `_light` as (1 - L) * LIGHT_MULT_TOWARD_WHITE.
DARK_MULT = 0.42
LIGHT_MULT_TOWARD_WHITE = 0.58

# `Derivations` (a Pydantic model) IS the single source of truth for the
# set of per-slot derivation names. Anywhere we need to iterate them we
# read `Derivations.model_fields` — no parallel string-tuple to drift
# out of sync.


class ColorDerivationService:
    """Expand each slot into a ``ColorOutput`` and assemble the flat
    recommendation palette. Stateless; one instance covers a whole run.

    Every helper is a ``@staticmethod`` on this class — the module has
    no loose functions besides the named constants above.
    """

    def build(self, schema: PaletteSchema) -> ColorPalette:
        """Project the corrected schema into the final ``ColorPalette``.

        Three phases:
        1. Compute the shared ``card`` / ``popup`` / ``divider`` once
           (per-slot derivations for bg/text reuse them by reference).
        2. Expand every slot into a full ``ColorOutput`` — base
           ``ColorValue`` + the six derivations.
        3. Assemble the flat recommendation ``palette`` with the
           "originals last" invariant.
        """
        bg_id = next(
            sid for sid, r in schema.roles.items() if r is ColorRole.BACKGROUND
        )
        text_id = next(
            sid for sid, r in schema.roles.items() if r is ColorRole.TEXT
        )
        dark_mode = schema.mode is ColorMode.DARK
        canvas = schema.colors[bg_id].oklch
        text = schema.colors[text_id].oklch

        shared_card_oklch = self._shared_card_oklch(canvas, dark_mode=dark_mode)
        shared_card = self._to_color_value(shared_card_oklch)
        shared_popup = self._to_color_value(
            self._compose_over(shared_card_oklch, canvas)
        )
        shared_divider = self._compute_shared_divider(canvas, text)

        colors = {
            sid: self._expand_one(
                slot=schema.colors[sid],
                role=schema.roles[sid],
                canvas=canvas,
                dark_mode=dark_mode,
                shared_card=shared_card,
                shared_popup=shared_popup,
            )
            for sid in schema.colors
        }

        return ColorPalette(
            mode=schema.mode,
            colors=colors,
            palette=self._build_recommendation_palette(
                colors,
                shared_card=shared_card,
                shared_popup=shared_popup,
                shared_divider=shared_divider,
            ),
        )

    # --- per-slot expansion ------------------------------------------------

    @classmethod
    def _expand_one(
        cls,
        *,
        slot,  # LLMSlotResponse
        role: ColorRole | None,
        canvas: OklchColor,
        dark_mode: bool,
        shared_card: ColorValue,
        shared_popup: ColorValue,
    ) -> ColorOutput:
        return ColorOutput(
            color=cls._to_color_value(slot.oklch),
            display_name=slot.display_name,
            description=slot.description,
            derivations=cls._compute_derivations(
                slot.oklch,
                role=role,
                canvas=canvas,
                dark_mode=dark_mode,
                shared_card=shared_card,
                shared_popup=shared_popup,
            ),
        )

    # --- the six derivations ----------------------------------------------

    @classmethod
    def _compute_derivations(
        cls,
        base: OklchColor,
        *,
        role: ColorRole | None,
        canvas: OklchColor,
        dark_mode: bool,
        shared_card: ColorValue,
        shared_popup: ColorValue,
    ) -> Derivations:
        # _second / _third: alpha tints (L/C/H preserved structurally).
        second = cls._with_alpha(base, SECOND_ALPHA)
        third = cls._with_alpha(base, THIRD_ALPHA)

        # _dark / _light: lightness shifts (C/H preserved structurally).
        dark = base.model_copy(
            update={"l": cls._compute_dark(base.l, canvas.l), "alpha": None}
        )
        light = base.model_copy(
            update={"l": cls._compute_light(base.l, canvas.l), "alpha": None}
        )

        # _card / _popup: shared for bg/text; chromatic for the rest.
        if role in (ColorRole.BACKGROUND, ColorRole.TEXT):
            card = shared_card
            popup = shared_popup
        else:
            card_alpha = cls._color_card_alpha(canvas.l, dark_mode=dark_mode)
            card_oklch = cls._with_alpha(base, card_alpha)
            card = cls._to_color_value(card_oklch)
            popup = cls._to_color_value(cls._compose_over(card_oklch, canvas))

        return Derivations(
            second=cls._to_color_value(second),
            third=cls._to_color_value(third),
            card=card,
            popup=popup,
            dark=cls._to_color_value(dark),
            light=cls._to_color_value(light),
        )

    # --- shared surfaces --------------------------------------------------

    @classmethod
    def _compute_shared_divider(
        cls, canvas: OklchColor, text: OklchColor
    ) -> ColorValue:
        """A separator line keyed to ``text`` with auto-contrast alpha
        (lifted from ``design_constants.dart:150-155``)."""
        alpha = min(0.22, max(0.10, 0.10 + 0.10 * canvas.l))
        return cls._to_color_value(cls._with_alpha(text, alpha))

    # --- the flat recommendation palette ----------------------------------

    @staticmethod
    def _build_recommendation_palette(
        colors: dict[str, ColorOutput],
        *,
        shared_card: ColorValue,
        shared_popup: ColorValue,
        shared_divider: ColorValue,
    ) -> dict[str, ColorValue]:
        """Order matters (the "no original gets overwritten" invariant):
        1. per-colour derivations flattened as ``<slot>_<deriv>``
        2. shared surfaces (``card``, ``popup``, ``divider``)
        3. base slot colours LAST — collisions fall to the base.
        """
        palette: dict[str, ColorValue] = {}
        for slot_id, color in colors.items():
            # Iterate Derivations.model_fields — the Pydantic model IS
            # the single source of truth for the six derivation names.
            for deriv_name in Derivations.model_fields:
                palette[f"{slot_id}_{deriv_name}"] = getattr(
                    color.derivations, deriv_name
                )
        palette["card"] = shared_card
        palette["popup"] = shared_popup
        palette["divider"] = shared_divider
        for slot_id, color in colors.items():
            palette[slot_id] = color.color
        return palette

    # --- coloraide helpers (static — no loose functions in the module) ---

    @staticmethod
    def _to_color_value(c: OklchColor) -> ColorValue:
        """OKLCH (struct) → ``ColorValue`` with every format. One
        round-trip through coloraide; each primitive does its own
        conversion."""
        aide = c.to_aide()
        return ColorValue(
            oklch=OklchColor.from_aide(aide),
            hsl=HslColor.from_aide(aide),
            rgb=RgbColor.from_aide(aide),
            hex=HexColor.from_aide(aide),
        )

    @staticmethod
    def _with_alpha(c: OklchColor, alpha: float) -> OklchColor:
        """Return ``c`` with its alpha set to ``alpha`` (0–1). L/C/H
        unchanged. Pydantic-only rewrite — no string juggling.

        Pydantic's ``model_copy(update=...)`` doesn't re-validate fields,
        so we range-check explicitly to keep the invariant the alpha
        field's ``ge=0/le=1`` guarantees on construction.
        """
        if not 0.0 <= alpha <= 1.0:
            raise ValueError(f"alpha must be 0–1; got {alpha!r}")
        return c.model_copy(update={"alpha": None if alpha >= 1.0 else alpha})

    @staticmethod
    def _compose_over(over: OklchColor, under: OklchColor) -> OklchColor:
        """Porter–Duff "over" via ``coloraide.Color.layer`` — composited
        in sRGB, returned as opaque OKLCH. ``under`` is treated as opaque
        (popups composite onto the canvas, not onto translucency)."""
        under_opaque = under.model_copy(update={"alpha": None})
        composited = Color.layer(
            [over.to_aide(), under_opaque.to_aide()], space="srgb"
        )
        return OklchColor.from_aide(composited).model_copy(
            update={"alpha": None}
        )

    # --- per-mode alpha + lightness formulas -----------------------------

    @staticmethod
    def _shared_card_alpha(canvas_L: float, *, dark_mode: bool) -> float:
        """Dark mode: the Dart elevation alpha (design_constants.dart:71-74).
        Light mode: a fresh mirror — a dark veil over a light canvas;
        Dart's formula collapses to whiter-than-white over a near-white
        canvas, which is the bug this rewrite fixes.
        """
        if dark_mode:
            return 0.06 + 0.5 * (canvas_L / 0.9)
        return 0.04 + 0.10 * (1.0 - canvas_L)

    @staticmethod
    def _color_card_alpha(canvas_L: float, *, dark_mode: bool) -> float:
        """Per-chromatic-slot card alpha. Larger than the white/black veil
        because tinted veils read weaker than neutral ones at the same
        alpha.
        """
        if dark_mode:
            return 0.10 + 0.20 * canvas_L
        return 0.08 + 0.10 * (1.0 - canvas_L)

    @classmethod
    def _shared_card_oklch(
        cls, canvas: OklchColor, *, dark_mode: bool
    ) -> OklchColor:
        """The translucent neutral veil over the canvas — white in dark
        mode, near-black in light mode. Chroma 0: reads as elevation,
        not as a tint."""
        alpha = cls._shared_card_alpha(canvas.l, dark_mode=dark_mode)
        veil_L = 0.98 if dark_mode else 0.08
        return OklchColor(l=veil_L, c=0.0, h=0.0, alpha=alpha)

    @staticmethod
    def _compute_dark(base_L: float, canvas_L: float) -> float:
        """``_dark`` lightness. Always lands below canvas L by ≥
        DARK_MIN_GAP."""
        ceiling = canvas_L - DARK_MIN_GAP
        return max(L_FLOOR, min(base_L * DARK_MULT, ceiling))

    @staticmethod
    def _compute_light(base_L: float, canvas_L: float) -> float:
        """``_light`` lightness. Always lands above canvas L by ≥
        LIGHT_MIN_GAP."""
        floor = canvas_L + LIGHT_MIN_GAP
        shifted_toward_white = base_L + (1.0 - base_L) * LIGHT_MULT_TOWARD_WHITE
        return min(L_CEIL, max(shifted_toward_white, floor))
