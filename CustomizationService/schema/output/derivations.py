"""Derivations — the seven deterministic per-colour variants the pipeline
produces alongside the base colour.

A Pydantic model on the Python side (one typed attribute per derivation,
so callers get attribute access and the schema is self-documenting); on
the wire it serializes as a plain ``{ second: ..., third: ... }`` dict —
that's the JSON shape frontends consume as a map.

``extra="ignore"`` matches the rest of the output models (``Output``,
``ColorPalette``, ``ImageOutput``): an externally- or previously-produced
``output.yaml`` carrying since-removed derivation keys still validates,
the stale keys silently dropped. Adding a new required derivation is a
deliberate breaking change.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict

from schema.output.color_value import ColorValue


class Derivations(BaseModel):
    """Seven deterministic variants of one base colour."""

    model_config = ConfigDict(extra="ignore")

    second: ColorValue  # 75% alpha tint (was text2nd in MobileApp)
    third: ColorValue  # 50% alpha tint (was text3rd)
    card: ColorValue  # translucent/tinted surface above the canvas
    popup: ColorValue  # opaque popup surface (card-over-canvas)
    dark: ColorValue  # darker variant, always below canvas L
    light: ColorValue  # lighter variant, always above canvas L
    regular_text: ColorValue  # readable colour for text painted ON this colour
