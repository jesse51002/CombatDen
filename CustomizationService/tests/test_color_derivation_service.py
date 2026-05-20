"""ColorDerivationService: structured primitives, format expansion, the
six derivations, and the flat recommendation-palette assembly.

Every helper that used to live in ``color_math.py`` is now a (static)
method on ``ColorDerivationService``, so tests dispatch through that
class via short aliases. Conversions + composition + contrast are
delegated to ``coloraide`` via the primitives' own ``to_aide`` /
``from_aide`` — the tests assert behaviour, not specific decimal places.
"""

from __future__ import annotations

import pytest
from pydantic import ValidationError

from schema import (
    ColorMode,
    ColorRole,
    ColorValue,
    HexColor,
    HslColor,
    OklchColor,
    RgbColor,
)
from schema.output.color_output import ColorOutput
from schema.output.derivations import Derivations
from src.modules.colors.color_derivation_service import ColorDerivationService
from src.modules.colors.color_models import PaletteSchema
from src.modules.colors.color_models import LLMSlotResponse

# Aliases for readability — every helper lives on the service class now.
_to_color_value = ColorDerivationService._to_color_value
_with_alpha = ColorDerivationService._with_alpha
_compose_over = ColorDerivationService._compose_over
_shared_card_oklch = ColorDerivationService._shared_card_oklch
_compute_dark = ColorDerivationService._compute_dark
_compute_light = ColorDerivationService._compute_light
_compute_shared_divider = ColorDerivationService._compute_shared_divider
_compute_derivations = ColorDerivationService._compute_derivations
_build_palette = ColorDerivationService._build_recommendation_palette


def _shared_card(canvas: OklchColor, *, dark_mode: bool) -> ColorValue:
    """Test seam: the shared card surface as a ``ColorValue`` (the
    composition `_to_color_value(_shared_card_oklch(...))` is now an
    implementation detail inside the service's `.build`)."""
    return _to_color_value(_shared_card_oklch(canvas, dark_mode=dark_mode))


def _shared_popup(canvas: OklchColor, *, dark_mode: bool) -> ColorValue:
    """Test seam: the opaque shared popup surface — card composited
    over canvas."""
    return _to_color_value(
        _compose_over(
            _shared_card_oklch(canvas, dark_mode=dark_mode), canvas
        )
    )


def _expand_color(
    oklch: OklchColor,
    display_name: str,
    description: str,
    *,
    role: ColorRole | None,
    canvas: OklchColor,
    dark_mode: bool,
    shared_card: ColorValue,
    shared_popup: ColorValue,
) -> ColorOutput:
    """Test seam: build one ColorOutput from primitives (the service's
    ``_expand_one`` takes a ``LLMSlotResponse`` — this wrapper saves
    constructing one in every test)."""
    return ColorDerivationService._expand_one(
        slot=LLMSlotResponse(
            oklch=oklch, display_name=display_name, description=description
        ),
        role=role,
        canvas=canvas,
        dark_mode=dark_mode,
        shared_card=shared_card,
        shared_popup=shared_popup,
    )

# --- format primitives -----------------------------------------------------


@pytest.mark.parametrize(
    "kwargs",
    [
        {"h": 0.0, "s": 0.0, "l": 0.0},
        {"h": 120.0, "s": 50.0, "l": 40.0},
        {"h": 359.5, "s": 99.9, "l": 0.1, "alpha": 0.25},
    ],
)
def test_hsl_color_accepts_valid(kwargs):
    HslColor(**kwargs)  # construction is the test


@pytest.mark.parametrize(
    "kwargs",
    [
        {"h": 400.0, "s": 50.0, "l": 40.0},  # H out of range
        {"h": 120.0, "s": 150.0, "l": 40.0},  # S out of range
        {"h": 120.0, "s": 50.0, "l": 40.0, "alpha": 1.5},  # alpha out of range
    ],
)
def test_hsl_color_rejects_invalid(kwargs):
    with pytest.raises(ValidationError):
        HslColor(**kwargs)


def test_hsl_color_from_css_round_trips():
    h = HslColor.from_css("hsl(120 50% 40%)")
    assert abs(h.h - 120.0) < 1e-3
    assert abs(h.s - 50.0) < 1e-3
    assert abs(h.l - 40.0) < 1e-3


@pytest.mark.parametrize(
    "kwargs",
    [
        {"r": 0, "g": 0, "b": 0},
        {"r": 255, "g": 128, "b": 64},
        {"r": 10, "g": 20, "b": 30, "alpha": 0.5},
    ],
)
def test_rgb_color_accepts_valid(kwargs):
    RgbColor(**kwargs)


@pytest.mark.parametrize(
    "kwargs",
    [
        {"r": 256, "g": 0, "b": 0},  # > 255
        {"r": -1, "g": 0, "b": 0},  # < 0
        {"r": 0, "g": 0, "b": 0, "alpha": 1.5},  # alpha out of range
    ],
)
def test_rgb_color_rejects_invalid(kwargs):
    with pytest.raises(ValidationError):
        RgbColor(**kwargs)


@pytest.mark.parametrize(
    "value",
    ["#000000", "#FFFFFF", "#1a2b3c", "#1A2B3C4D", "#deadbe", "#deadbeef"],
)
def test_hex_color_accepts_valid(value):
    assert str(HexColor.model_validate(value)) == value


@pytest.mark.parametrize(
    "value",
    [
        "000000",  # no leading #
        "#abc",  # 3-digit short form NOT accepted
        "#12345",  # 5 digits
        "#1234567",  # 7 digits
        "#GGGGGG",  # non-hex chars
    ],
)
def test_hex_color_rejects_invalid(value):
    with pytest.raises(ValidationError):
        HexColor.model_validate(value)


# --- conversions (every primitive does its own round-trip) ---------------


def test_oklch_to_rgb_anchors():
    # Pure white / black round-trip into clean rgb anchors.
    rgb_w = RgbColor.from_aide(OklchColor(l=1.0, c=0.0, h=0.0).to_aide())
    rgb_k = RgbColor.from_aide(OklchColor(l=0.0, c=0.0, h=0.0).to_aide())
    assert (rgb_w.r, rgb_w.g, rgb_w.b) == (255, 255, 255)
    assert (rgb_k.r, rgb_k.g, rgb_k.b) == (0, 0, 0)


def test_oklch_to_hex_anchors():
    hex_w = HexColor.from_aide(OklchColor(l=1.0, c=0.0, h=0.0).to_aide())
    hex_k = HexColor.from_aide(OklchColor(l=0.0, c=0.0, h=0.0).to_aide())
    assert str(hex_w) == "#ffffff"
    assert str(hex_k) == "#000000"
    # Partial alpha → 8-digit form.
    hex_alpha = HexColor.from_aide(
        OklchColor(l=1.0, c=0.0, h=0.0, alpha=0.5).to_aide()
    )
    assert len(str(hex_alpha)) == 9 and str(hex_alpha).startswith("#")


def test_oklch_to_hsl_white_black():
    hsl_w = HslColor.from_aide(OklchColor(l=1.0, c=0.0, h=0.0).to_aide())
    hsl_k = HslColor.from_aide(OklchColor(l=0.0, c=0.0, h=0.0).to_aide())
    # White: saturation 0, lightness 100.
    assert abs(hsl_w.s) < 1e-3
    assert abs(hsl_w.l - 100.0) < 1e-3
    # Black: saturation 0, lightness 0.
    assert abs(hsl_k.s) < 1e-3
    assert abs(hsl_k.l) < 1e-3


def test_to_color_value_bundles_every_format():
    cv = _to_color_value(OklchColor(l=0.5, c=0.1, h=200.0))
    assert isinstance(cv, ColorValue)
    assert isinstance(cv.oklch, OklchColor)
    assert isinstance(cv.hsl, HslColor)
    assert isinstance(cv.rgb, RgbColor)
    assert isinstance(cv.hex, HexColor)
    # The OKLCH round-trips back to (approximately) the input.
    assert abs(cv.oklch.l - 0.5) < 1e-6
    assert abs(cv.oklch.c - 0.1) < 1e-6


# --- typed mutators ------------------------------------------------------


def test_oklch_with_alpha_sets_field_preserves_lch():
    out = _with_alpha(OklchColor(l=0.7, c=0.12, h=240.0), 0.5)
    assert out.l == 0.7
    assert out.c == 0.12
    assert out.h == 240.0
    assert out.alpha == 0.5


def test_oklch_with_alpha_full_strips_alpha_to_none():
    out = _with_alpha(OklchColor(l=0.7, c=0.12, h=240.0), 1.0)
    assert out.alpha is None


def test_oklch_with_alpha_rejects_out_of_range():
    with pytest.raises(ValueError):
        _with_alpha(OklchColor(l=0.5, c=0.1, h=200.0), 1.5)


def test_oklch_lightness_rewrite_via_model_copy_preserves_rest():
    """The dedicated `oklch_with_lightness` helper is gone — Pydantic's
    own ``model_copy(update={"l": ...})`` is the canonical way to rewrite
    one field. This test pins that pattern so the derivation service can
    keep relying on it (`_compute_dark` / `_compute_light` use it
    directly)."""
    src = OklchColor(l=0.7, c=0.123, h=245.6, alpha=0.5)
    out = src.model_copy(update={"l": 0.30})
    assert out.l == 0.30
    assert out.c == 0.123
    assert out.h == 245.6
    assert out.alpha == 0.5


# --- compose_over --------------------------------------------------------


def test_compose_over_zero_alpha_is_under():
    """Translucent at alpha=0 vanishes — the under colour is what shows."""
    under = OklchColor(l=0.5, c=0.0, h=0.0)
    over_clear = _with_alpha(OklchColor(l=1.0, c=0.0, h=0.0), 0.0)
    out = _compose_over(over_clear, under)
    # Compose-over is opaque (alpha is None).
    assert out.alpha is None
    # Should approximately match under (L ≈ 0.5, neutral).
    assert abs(out.l - 0.5) < 1e-2
    assert out.c < 0.01


def test_compose_over_full_alpha_is_over():
    """Opaque "over" obliterates "under"."""
    over = OklchColor(l=0.5, c=0.0, h=0.0)
    under = OklchColor(l=0.1, c=0.0, h=0.0)
    out = _compose_over(over, under)
    assert abs(out.l - 0.5) < 1e-2


def test_compose_over_output_is_always_opaque():
    """Even with partial alpha on "over", the composite is fully opaque."""
    over = _with_alpha(OklchColor(l=0.98, c=0.0, h=0.0), 0.20)
    under = OklchColor(l=0.15, c=0.0, h=0.0)
    out = _compose_over(over, under)
    assert out.alpha is None


# --- shared surfaces -----------------------------------------------------


def test_shared_card_dark_mode_is_translucent_white():
    canvas = OklchColor(l=0.15, c=0.01, h=200.0)
    card = _shared_card(canvas, dark_mode=True)
    assert card.oklch.alpha is not None and 0.05 < card.oklch.alpha < 0.20
    assert card.oklch.l > 0.9 and card.oklch.c < 0.01  # near-white, neutral


def test_shared_card_light_mode_is_translucent_dark():
    canvas = OklchColor(l=0.88, c=0.01, h=80.0)
    card = _shared_card(canvas, dark_mode=False)
    assert card.oklch.alpha is not None and 0.02 < card.oklch.alpha < 0.12
    assert card.oklch.l < 0.15 and card.oklch.c < 0.01  # near-black, neutral


def test_shared_popup_is_opaque():
    canvas = OklchColor(l=0.15, c=0.01, h=200.0)
    popup = _shared_popup(canvas, dark_mode=True)
    assert popup.oklch.alpha is None


def test_shared_divider_uses_text_with_auto_contrast_alpha():
    canvas = OklchColor(l=0.15, c=0.01, h=200.0)
    text = OklchColor(l=0.92, c=0.01, h=80.0)
    divider = _compute_shared_divider(canvas, text)
    assert divider.oklch.alpha is not None and 0.10 <= divider.oklch.alpha <= 0.22
    # Lightness inherited from text — the divider IS the text colour.
    assert abs(divider.oklch.l - 0.92) < 1e-3


# --- per-slot derivations ------------------------------------------------


def _shared_pair(canvas: OklchColor, *, dark_mode: bool):
    return (
        _shared_card(canvas, dark_mode=dark_mode),
        _shared_popup(canvas, dark_mode=dark_mode),
    )


@pytest.mark.parametrize("dark_mode", [True, False], ids=["dark", "light"])
def test_derivations_is_typed_with_exact_field_set(dark_mode):
    canvas = (
        OklchColor(l=0.15, c=0.01, h=200.0)
        if dark_mode
        else OklchColor(l=0.88, c=0.01, h=80.0)
    )
    card, popup = _shared_pair(canvas, dark_mode=dark_mode)
    out = _compute_derivations(
        OklchColor(l=0.60, c=0.18, h=30.0),
        role=None,
        canvas=canvas,
        dark_mode=dark_mode,
        shared_card=card,
        shared_popup=popup,
    )
    # `Derivations` is a typed Pydantic model with one attribute per
    # derivation. The model's field set and the canonical tuple must
    # match — that's the contract palette assembly depends on.
    assert set(Derivations.model_fields) == set(Derivations.model_fields) == {
        "second", "third", "card", "popup", "dark", "light",
    }
    assert isinstance(out, Derivations)


def test_second_and_third_preserve_lch_only_change_alpha():
    canvas = OklchColor(l=0.15, c=0.01, h=200.0)
    card, popup = _shared_pair(canvas, dark_mode=True)
    base = OklchColor(l=0.60, c=0.18, h=30.0)
    out = _compute_derivations(
        base,
        role=None,
        canvas=canvas,
        dark_mode=True,
        shared_card=card,
        shared_popup=popup,
    )
    assert out.second.oklch.l == 0.60
    assert out.second.oklch.c == 0.18
    assert out.second.oklch.h == 30.0
    assert out.second.oklch.alpha == 0.75
    assert out.third.oklch.alpha == 0.50


def test_bg_and_text_roles_use_shared_card_and_popup():
    canvas = OklchColor(l=0.15, c=0.01, h=200.0)
    card, popup = _shared_pair(canvas, dark_mode=True)
    for role in (ColorRole.BACKGROUND, ColorRole.TEXT):
        out = _compute_derivations(
            OklchColor(l=0.60, c=0.01, h=200.0),
            role=role,
            canvas=canvas,
            dark_mode=True,
            shared_card=card,
            shared_popup=popup,
        )
        # Identity, not just equality — the same ColorValue instance is
        # threaded through (free assertion that the shared math is wired).
        assert out.card is card
        assert out.popup is popup


def test_chromatic_card_is_translucent_brand_tint():
    canvas = OklchColor(l=0.15, c=0.01, h=200.0)
    card, popup = _shared_pair(canvas, dark_mode=True)
    base = OklchColor(l=0.60, c=0.20, h=30.0)
    out = _compute_derivations(
        base,
        role=None,
        canvas=canvas,
        dark_mode=True,
        shared_card=card,
        shared_popup=popup,
    )
    # Hue + chroma + lightness come from the base; only alpha was added.
    assert out.card.oklch.alpha is not None and 0.05 < out.card.oklch.alpha < 0.40
    assert abs(out.card.oklch.l - 0.60) < 1e-3
    assert abs(out.card.oklch.c - 0.20) < 1e-3
    assert abs(out.card.oklch.h - 30.0) < 1e-3
    # Popup composites that over the canvas — opaque output.
    assert out.popup.oklch.alpha is None


@pytest.mark.parametrize("dark_mode", [True, False], ids=["dark", "light"])
def test_dark_is_always_below_canvas_light_always_above(dark_mode):
    canvas = (
        OklchColor(l=0.15, c=0.01, h=200.0)
        if dark_mode
        else OklchColor(l=0.88, c=0.01, h=80.0)
    )
    card, popup = _shared_pair(canvas, dark_mode=dark_mode)
    # Try a few base colours across the lightness spectrum.
    for base_L in (0.10, 0.35, 0.60, 0.85):
        base = OklchColor(l=base_L, c=0.15, h=320.0)
        out = _compute_derivations(
            base,
            role=None,
            canvas=canvas,
            dark_mode=dark_mode,
            shared_card=card,
            shared_popup=popup,
        )
        assert out.dark.oklch.l < canvas.l, (
            f"_dark.l {out.dark.oklch.l} not below canvas {canvas.l} "
            f"(base L {base_L}, mode={'dark' if dark_mode else 'light'})"
        )
        assert out.light.oklch.l > canvas.l, (
            f"_light.l {out.light.oklch.l} not above canvas {canvas.l} "
            f"(base L {base_L}, mode={'dark' if dark_mode else 'light'})"
        )


# --- the flat recommendation palette --------------------------------------


def _expand(
    slot_id: str,
    oklch: OklchColor,
    role: ColorRole | None,
    *,
    canvas: OklchColor,
    dark_mode: bool,
    card: ColorValue,
    popup: ColorValue,
) -> ColorOutput:
    return _expand_color(
        oklch=oklch,
        display_name=f"{slot_id} tone",
        description=f"the {slot_id} slot",
        role=role,
        canvas=canvas,
        dark_mode=dark_mode,
        shared_card=card,
        shared_popup=popup,
    )


def _full_palette(
    dark_mode: bool,
) -> tuple[dict[str, ColorOutput], dict[str, ColorValue]]:
    canvas = (
        OklchColor(l=0.15, c=0.01, h=200.0)
        if dark_mode
        else OklchColor(l=0.88, c=0.01, h=80.0)
    )
    text = (
        OklchColor(l=0.92, c=0.01, h=80.0)
        if dark_mode
        else OklchColor(l=0.20, c=0.01, h=250.0)
    )
    card, popup = _shared_pair(canvas, dark_mode=dark_mode)
    divider = _compute_shared_divider(canvas, text)
    colors = {
        "primary": _expand(
            "primary", OklchColor(l=0.60, c=0.18, h=30.0), None,
            canvas=canvas, dark_mode=dark_mode, card=card, popup=popup,
        ),
        "accent": _expand(
            "accent", OklchColor(l=0.70, c=0.16, h=280.0), None,
            canvas=canvas, dark_mode=dark_mode, card=card, popup=popup,
        ),
        "background": _expand(
            "background", canvas, ColorRole.BACKGROUND,
            canvas=canvas, dark_mode=dark_mode, card=card, popup=popup,
        ),
        "text": _expand(
            "text", text, ColorRole.TEXT,
            canvas=canvas, dark_mode=dark_mode, card=card, popup=popup,
        ),
    }
    palette = _build_palette(
        colors,
        shared_card=card,
        shared_popup=popup,
        shared_divider=divider,
    )
    return colors, palette


def test_palette_contains_every_derivation_for_every_slot():
    colors, palette = _full_palette(dark_mode=True)
    for slot_id in colors:
        for deriv in Derivations.model_fields:
            assert f"{slot_id}_{deriv}" in palette


def test_palette_contains_shared_surfaces():
    _, palette = _full_palette(dark_mode=True)
    assert {"card", "popup", "divider"}.issubset(palette.keys())


def test_palette_base_slots_win_collisions():
    """The user's "no original gets overwritten" invariant: base slot
    entries are appended last so any derivation-key collision falls to
    the base."""
    colors, palette = _full_palette(dark_mode=True)
    for slot_id, color in colors.items():
        assert slot_id in palette
        assert palette[slot_id] == color.color
