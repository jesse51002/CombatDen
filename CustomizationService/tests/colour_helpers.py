"""Shared test helper: build a full ``ColorPalette`` from a hand-built
``LLMPalette``.

Mirrors the deterministic (post-LLM) body of ``ColorNode.run``: shared
surfaces → per-slot atomic expand → flat recommendation palette. Several
test modules need a fully-populated palette as a fixture without standing
up the LLM; this is the one place that assembly lives for tests, so a
change to the node's orchestration only needs mirroring here.
"""

from __future__ import annotations

from schema import ColorPalette
from src.modules.colors.color_derivation_service import ColorDerivationService
from src.modules.colors.color_models import LLMPalette
from src.modules.colors.color_node import ColorNode
from src.modules.colors.color_surface_service import ColorSurfaceService


def assemble_color_palette(schema: LLMPalette) -> ColorPalette:
    """A (corrected) ``LLMPalette`` → the final ``ColorPalette``."""
    surfaces = ColorSurfaceService().compute(
        canvas=schema.canvas, text=schema.text, dark_mode=schema.dark_mode
    )
    derive = ColorDerivationService()
    colors = {
        sid: derive.expand(
            schema.colors[sid],
            role=schema.roles[sid],
            canvas=schema.canvas,
            dark_mode=schema.dark_mode,
            surfaces=surfaces,
        )
        for sid in schema.colors
    }
    return ColorPalette(
        mode=schema.mode,
        colors=colors,
        palette=ColorNode.create_palette(colors, surfaces),
    )
