"""ColorDerivationService: the atomic per-colour expansion, plus the
node's flat recommendation-palette assembly that consumes it.

``expand`` is the only public method — one resolved slot → its
``ColorOutput`` (base value + the six derivations). The shared surfaces
it needs (for the background + text slots) come from
``ColorSurfaceService``; the flat palette assembly is the node's job
(``ColorNode._recommend``). Both are exercised here against the
production code, not re-implemented.
"""

from __future__ import annotations

import pytest

from schema import ColorMode, ColorPalette, ColorRole, OklchColor
from schema.output.color_output import ColorOutput
from schema.output.derivations import Derivations
from src.modules.colors.color_derivation_service import ColorDerivationService
from src.modules.colors.color_models import LLMSlotResponse, LLMPalette
from src.modules.colors.color_node import ColorNode
from src.modules.colors.color_surface_service import (
    ColorSurfaceService,
    SharedSurfaces,
)
from tests.colour_helpers import assemble_color_palette

_DERIVE = ColorDerivationService()
_SURFACES = ColorSurfaceService()

_DARK_CANVAS = OklchColor(l=0.15, c=0.01, h=200.0)
_LIGHT_CANVAS = OklchColor(l=0.88, c=0.01, h=80.0)
_DARK_TEXT = OklchColor(l=0.92, c=0.01, h=80.0)
_LIGHT_TEXT = OklchColor(l=0.20, c=0.01, h=250.0)


def _surfaces(*, dark_mode: bool) -> SharedSurfaces:
    canvas = _DARK_CANVAS if dark_mode else _LIGHT_CANVAS
    text = _DARK_TEXT if dark_mode else _LIGHT_TEXT
    return _SURFACES.compute(canvas=canvas, text=text, dark_mode=dark_mode)


def _expand(
    oklch: OklchColor,
    *,
    role: ColorRole | None,
    dark_mode: bool,
    surfaces: SharedSurfaces,
    name: str = "slot",
) -> ColorOutput:
    canvas = _DARK_CANVAS if dark_mode else _LIGHT_CANVAS
    return _DERIVE.expand(
        LLMSlotResponse(oklch=oklch, display_name=f"{name} tone", description=name),
        role=role,
        canvas=canvas,
        dark_mode=dark_mode,
        surfaces=surfaces,
    )


# --- expand: shape --------------------------------------------------------


@pytest.mark.parametrize("dark_mode", [True, False], ids=["dark", "light"])
def test_expand_produces_coloroutput_with_six_typed_derivations(dark_mode):
    out = _expand(
        OklchColor(l=0.60, c=0.18, h=30.0),
        role=None,
        dark_mode=dark_mode,
        surfaces=_surfaces(dark_mode=dark_mode),
    )
    assert isinstance(out, ColorOutput)
    assert isinstance(out.derivations, Derivations)
    # `Derivations` is the source of truth for the six names.
    assert set(Derivations.model_fields) == {
        "second", "third", "card", "popup", "dark", "light",
    }


def test_second_and_third_preserve_lch_only_change_alpha():
    out = _expand(
        OklchColor(l=0.60, c=0.18, h=30.0),
        role=None,
        dark_mode=True,
        surfaces=_surfaces(dark_mode=True),
    )
    assert out.derivations.second.oklch.l == 0.60
    assert out.derivations.second.oklch.c == 0.18
    assert out.derivations.second.oklch.h == 30.0
    assert out.derivations.second.oklch.alpha == 0.75
    assert out.derivations.third.oklch.alpha == 0.50


def test_bg_and_text_roles_reuse_shared_card_and_popup():
    surfaces = _surfaces(dark_mode=True)
    for role in (ColorRole.BACKGROUND, ColorRole.TEXT):
        out = _expand(
            OklchColor(l=0.60, c=0.01, h=200.0),
            role=role,
            dark_mode=True,
            surfaces=surfaces,
        )
        # Identity, not just equality — the shared surface instance is
        # threaded straight through for these roles.
        assert out.derivations.card is surfaces.card
        assert out.derivations.popup is surfaces.popup


def test_chromatic_card_is_translucent_brand_tint():
    out = _expand(
        OklchColor(l=0.60, c=0.20, h=30.0),
        role=None,
        dark_mode=True,
        surfaces=_surfaces(dark_mode=True),
    )
    card = out.derivations.card.oklch
    assert card.alpha is not None and 0.05 < card.alpha < 0.40
    assert abs(card.l - 0.60) < 1e-3
    assert abs(card.c - 0.20) < 1e-3
    assert abs(card.h - 30.0) < 1e-3
    # Popup composites that over the canvas — opaque.
    assert out.derivations.popup.oklch.alpha is None


@pytest.mark.parametrize("dark_mode", [True, False], ids=["dark", "light"])
def test_dark_below_canvas_light_above(dark_mode):
    canvas = _DARK_CANVAS if dark_mode else _LIGHT_CANVAS
    surfaces = _surfaces(dark_mode=dark_mode)
    for base_l in (0.10, 0.35, 0.60, 0.85):
        out = _expand(
            OklchColor(l=base_l, c=0.15, h=320.0),
            role=None,
            dark_mode=dark_mode,
            surfaces=surfaces,
        )
        assert out.derivations.dark.oklch.l < canvas.l, (
            f"dark.l {out.derivations.dark.oklch.l} not below canvas "
            f"{canvas.l} (base {base_l}, dark={dark_mode})"
        )
        assert out.derivations.light.oklch.l > canvas.l, (
            f"light.l {out.derivations.light.oklch.l} not above canvas "
            f"{canvas.l} (base {base_l}, dark={dark_mode})"
        )


# --- flat recommendation palette (via ColorNode.assemble) -----------------


def _full_palette(dark_mode: bool) -> ColorPalette:
    """Run the node's deterministic assembly over a hand-built schema —
    the same path production takes after the LLM + correction steps."""
    canvas = _DARK_CANVAS if dark_mode else _LIGHT_CANVAS
    text = _DARK_TEXT if dark_mode else _LIGHT_TEXT
    schema = LLMPalette(
        mode=ColorMode.DARK if dark_mode else ColorMode.LIGHT,
        roles={
            "primary": None,
            "accent": None,
            "background": ColorRole.BACKGROUND,
            "text": ColorRole.TEXT,
        },
        colors={
            "primary": LLMSlotResponse(
                oklch=OklchColor(l=0.60, c=0.18, h=30.0),
                display_name="primary", description="primary",
            ),
            "accent": LLMSlotResponse(
                oklch=OklchColor(l=0.70, c=0.16, h=280.0),
                display_name="accent", description="accent",
            ),
            "background": LLMSlotResponse(
                oklch=canvas, display_name="background", description="bg",
            ),
            "text": LLMSlotResponse(
                oklch=text, display_name="text", description="text",
            ),
        },
    )
    return assemble_color_palette(schema)


def test_palette_contains_every_derivation_for_every_slot():
    out = _full_palette(dark_mode=True)
    for slot_id in out.colors:
        for deriv in Derivations.model_fields:
            assert f"{slot_id}_{deriv}" in out.palette


def test_palette_contains_shared_surfaces():
    out = _full_palette(dark_mode=True)
    assert {"card", "popup", "divider"}.issubset(out.palette.keys())


def test_palette_base_slots_win_collisions():
    """The "no original gets overwritten" invariant: base slot entries are
    appended last so any derivation-key collision falls to the base."""
    out = _full_palette(dark_mode=True)
    for slot_id, color in out.colors.items():
        assert slot_id in out.palette
        assert out.palette[slot_id] == color.color
