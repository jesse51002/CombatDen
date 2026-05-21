"""ColorValue — one colour expressed in every supported format.

The shared "what a colour value looks like on the wire" struct. Used
uniformly for base-colour bodies (via composition on ``ColorOutput.color``),
every per-colour derivation, and every entry in the flat recommendation
``palette``. The pipeline always populates every format from the canonical
``OklchColor``; consumers pick whichever they need (the MobileApp parses
oklch today; web consumers often prefer hex; design tools want hsl/rgb).

This is the single point of change for adding another format (P3, Lab,
etc.) later — schema callers don't need to know more than "a colour value
holds N formats".
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict

from schema.primitives import HexColor, HslColor, OklchColor, RgbColor


class ColorValue(BaseModel):
    """One colour, in every format the pipeline emits."""

    model_config = ConfigDict(extra="forbid")

    oklch: OklchColor
    hsl: HslColor
    rgb: RgbColor
    hex: HexColor

    @classmethod
    def from_oklch(cls, c: OklchColor) -> ColorValue:
        """Build a ``ColorValue`` (every format) from one ``OklchColor``.

        One coloraide round-trip; each primitive does its own conversion.
        This is the single "OKLCH → all formats" constructor — the colour
        services call it rather than re-deriving the projection.
        """
        aide = c.to_aide()
        return cls(
            oklch=OklchColor.from_aide(aide),
            hsl=HslColor.from_aide(aide),
            rgb=RgbColor.from_aide(aide),
            hex=HexColor.from_aide(aide),
        )
