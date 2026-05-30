"""Structured colour primitives + ColorValue: validation, CSS round-trip,
format conversions, and the colour ops that live on the types
themselves (``OklchColor.with_alpha`` / ``composite_over`` and
``ColorValue.from_oklch``).

Conversions are delegated to ``coloraide`` via each primitive's
``to_aide`` / ``from_aide`` — the tests assert behaviour, not specific
decimal places.
"""

from __future__ import annotations

import pytest
from pydantic import ValidationError

from schema import ColorValue, HexColor, HslColor, OklchColor, RgbColor

# --- OklchColor ------------------------------------------------------------


@pytest.mark.parametrize(
    "kwargs",
    [
        {"l": 0.60, "c": 0.12, "h": 250.0},
        {"l": 0.50, "c": 0.10, "h": 120.0, "alpha": 0.5},
        {"l": 0.0, "c": 0.0, "h": 0.0},  # pure black
        {"l": 1.0, "c": 0.0, "h": 0.0},  # pure white
    ],
)
def test_oklch_accepts_valid(kwargs):
    OklchColor(**kwargs)


@pytest.mark.parametrize(
    "kwargs",
    [
        {"l": -0.1, "c": 0.1, "h": 10.0},  # L below 0
        {"l": 1.5, "c": 0.1, "h": 10.0},  # L above 1
        {"l": 0.5, "c": 0.9, "h": 10.0},  # C above 0.5
        {"l": 0.5, "c": 0.1, "h": 400.0},  # H above 360
        {"l": 0.5, "c": 0.1, "h": 10.0, "alpha": 1.5},  # alpha out of range
    ],
)
def test_oklch_rejects_invalid(kwargs):
    with pytest.raises(ValidationError):
        OklchColor(**kwargs)


def test_oklch_from_css_round_trips():
    o = OklchColor.from_css("oklch(70% 0.19 41)")
    assert abs(o.l - 0.70) < 1e-6
    assert abs(o.c - 0.19) < 1e-6
    assert abs(o.h - 41.0) < 1e-3
    assert str(o) == "oklch(70% 0.19 41)"


def test_oklch_str_form_matches_css():
    assert str(OklchColor(l=0.5, c=0.1, h=200.0)) == "oklch(50% 0.1 200)"
    assert (
        str(OklchColor(l=0.5, c=0.1, h=200.0, alpha=0.25))
        == "oklch(50% 0.1 200 / 0.25)"
    )


# --- HslColor / RgbColor / HexColor ---------------------------------------


@pytest.mark.parametrize(
    "kwargs",
    [
        {"h": 0.0, "s": 0.0, "l": 0.0},
        {"h": 120.0, "s": 50.0, "l": 40.0},
        {"h": 359.5, "s": 99.9, "l": 0.1, "alpha": 0.25},
    ],
)
def test_hsl_accepts_valid(kwargs):
    HslColor(**kwargs)


@pytest.mark.parametrize(
    "kwargs",
    [
        {"h": 400.0, "s": 50.0, "l": 40.0},
        {"h": 120.0, "s": 150.0, "l": 40.0},
        {"h": 120.0, "s": 50.0, "l": 40.0, "alpha": 1.5},
    ],
)
def test_hsl_rejects_invalid(kwargs):
    with pytest.raises(ValidationError):
        HslColor(**kwargs)


def test_hsl_from_css_round_trips():
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
def test_rgb_accepts_valid(kwargs):
    RgbColor(**kwargs)


@pytest.mark.parametrize(
    "kwargs",
    [
        {"r": 256, "g": 0, "b": 0},
        {"r": -1, "g": 0, "b": 0},
        {"r": 0, "g": 0, "b": 0, "alpha": 1.5},
    ],
)
def test_rgb_rejects_invalid(kwargs):
    with pytest.raises(ValidationError):
        RgbColor(**kwargs)


@pytest.mark.parametrize(
    "value",
    ["#000000", "#FFFFFF", "#1a2b3c", "#1A2B3C4D", "#deadbe", "#deadbeef"],
)
def test_hex_accepts_valid(value):
    assert str(HexColor.model_validate(value)) == value


@pytest.mark.parametrize(
    "value",
    ["000000", "#abc", "#12345", "#1234567", "#GGGGGG"],
)
def test_hex_rejects_invalid(value):
    with pytest.raises(ValidationError):
        HexColor.model_validate(value)


# --- conversions (each primitive does its own round-trip via coloraide) ---


def test_oklch_to_rgb_anchors():
    rgb_w = RgbColor.from_aide(OklchColor(l=1.0, c=0.0, h=0.0).to_aide())
    rgb_k = RgbColor.from_aide(OklchColor(l=0.0, c=0.0, h=0.0).to_aide())
    assert (rgb_w.r, rgb_w.g, rgb_w.b) == (255, 255, 255)
    assert (rgb_k.r, rgb_k.g, rgb_k.b) == (0, 0, 0)


def test_oklch_to_hex_anchors():
    assert str(HexColor.from_aide(OklchColor(l=1.0, c=0.0, h=0.0).to_aide())) == "#ffffff"
    assert str(HexColor.from_aide(OklchColor(l=0.0, c=0.0, h=0.0).to_aide())) == "#000000"
    hex_alpha = HexColor.from_aide(
        OklchColor(l=1.0, c=0.0, h=0.0, alpha=0.5).to_aide()
    )
    assert len(str(hex_alpha)) == 9 and str(hex_alpha).startswith("#")


def test_oklch_to_hsl_white_black():
    hsl_w = HslColor.from_aide(OklchColor(l=1.0, c=0.0, h=0.0).to_aide())
    hsl_k = HslColor.from_aide(OklchColor(l=0.0, c=0.0, h=0.0).to_aide())
    assert abs(hsl_w.s) < 1e-3 and abs(hsl_w.l - 100.0) < 1e-3
    assert abs(hsl_k.s) < 1e-3 and abs(hsl_k.l) < 1e-3


# --- ColorValue.from_oklch ------------------------------------------------


def test_color_value_from_oklch_bundles_every_format():
    cv = ColorValue.from_oklch(OklchColor(l=0.5, c=0.1, h=200.0))
    assert isinstance(cv, ColorValue)
    assert isinstance(cv.oklch, OklchColor)
    assert isinstance(cv.hsl, HslColor)
    assert isinstance(cv.rgb, RgbColor)
    assert isinstance(cv.hex, HexColor)
    assert abs(cv.oklch.l - 0.5) < 1e-6
    assert abs(cv.oklch.c - 0.1) < 1e-6


# --- OklchColor.with_alpha ------------------------------------------------


def test_with_alpha_sets_field_preserves_lch():
    out = OklchColor(l=0.7, c=0.12, h=240.0).with_alpha(0.5)
    assert (out.l, out.c, out.h, out.alpha) == (0.7, 0.12, 240.0, 0.5)


def test_with_alpha_full_strips_to_none():
    assert OklchColor(l=0.7, c=0.12, h=240.0).with_alpha(1.0).alpha is None


def test_with_alpha_rejects_out_of_range():
    with pytest.raises(ValueError):
        OklchColor(l=0.5, c=0.1, h=200.0).with_alpha(1.5)


# --- OklchColor.composite_over --------------------------------------------


def test_composite_over_zero_alpha_is_under():
    """Translucent at alpha=0 vanishes — the under colour shows through."""
    under = OklchColor(l=0.5, c=0.0, h=0.0)
    over_clear = OklchColor(l=1.0, c=0.0, h=0.0).with_alpha(0.0)
    out = over_clear.composite_over(under)
    assert out.alpha is None  # composite is opaque
    assert abs(out.l - 0.5) < 1e-2 and out.c < 0.01


def test_composite_over_full_alpha_is_over():
    """Opaque "over" obliterates "under"."""
    out = OklchColor(l=0.5, c=0.0, h=0.0).composite_over(
        OklchColor(l=0.1, c=0.0, h=0.0)
    )
    assert abs(out.l - 0.5) < 1e-2


def test_composite_over_is_always_opaque():
    out = OklchColor(l=0.98, c=0.0, h=0.0).with_alpha(0.20).composite_over(
        OklchColor(l=0.15, c=0.0, h=0.0)
    )
    assert out.alpha is None
