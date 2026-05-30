"""ColorSurfaceService: the run-wide shared surfaces (card/popup/divider).

The alpha formulas are mode-aware; the tests assert the shape (neutral
translucent veil, opaque popup, text-keyed divider) rather than exact
decimals.
"""

from __future__ import annotations

from schema import OklchColor
from src.modules.colors.color_surface_service import (
    ColorSurfaceService,
    SharedSurfaces,
)

_SERVICE = ColorSurfaceService()


def _compute(canvas: OklchColor, text: OklchColor, *, dark_mode: bool) -> SharedSurfaces:
    return _SERVICE.compute(canvas=canvas, text=text, dark_mode=dark_mode)


def test_card_dark_mode_is_translucent_white():
    s = _compute(
        OklchColor(l=0.15, c=0.01, h=200.0),
        OklchColor(l=0.92, c=0.01, h=80.0),
        dark_mode=True,
    )
    assert s.card.oklch.alpha is not None and 0.05 < s.card.oklch.alpha < 0.20
    assert s.card.oklch.l > 0.9 and s.card.oklch.c < 0.01  # near-white, neutral


def test_card_light_mode_is_translucent_dark():
    s = _compute(
        OklchColor(l=0.88, c=0.01, h=80.0),
        OklchColor(l=0.20, c=0.01, h=250.0),
        dark_mode=False,
    )
    assert s.card.oklch.alpha is not None and 0.02 < s.card.oklch.alpha < 0.12
    assert s.card.oklch.l < 0.15 and s.card.oklch.c < 0.01  # near-black, neutral


def test_popup_is_opaque():
    s = _compute(
        OklchColor(l=0.15, c=0.01, h=200.0),
        OklchColor(l=0.92, c=0.01, h=80.0),
        dark_mode=True,
    )
    assert s.popup.oklch.alpha is None


def test_divider_uses_text_with_auto_contrast_alpha():
    text = OklchColor(l=0.92, c=0.01, h=80.0)
    s = _compute(OklchColor(l=0.15, c=0.01, h=200.0), text, dark_mode=True)
    assert s.divider.oklch.alpha is not None
    assert 0.10 <= s.divider.oklch.alpha <= 0.22
    # Lightness inherited from text — the divider IS the text colour.
    assert abs(s.divider.oklch.l - 0.92) < 1e-3
