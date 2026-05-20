"""Typed colour + path primitives.

Three of the colour primitives are STRUCTURED Pydantic models — each
channel is its own typed field. They serialize to JSON / YAML as nested
objects (``{l: 0.705, c: 0.19, h: 41}``) rather than CSS strings, so
neither this codebase nor consumers have to parse / re-emit the CSS
form. The pipeline does all colour math on ``coloraide.Color`` objects;
the structured primitives are the wire-boundary type and know how to
round-trip themselves through coloraide.

The shared parent ``CssColor`` requires every structured subclass to
implement that round-trip (``to_aide`` / ``from_aide``) and a canonical
CSS string form. Doing this on the primitive itself — rather than in
free functions somewhere downstream — means the colour math callsite is
always ``c.to_aide()`` … then back via ``cls.from_aide(...)``.

``HexColor`` is the deliberate string exception. Hex IS naturally a
string — ``#fd6d31`` — and splitting it into ``{r, g, b}`` ints would
just duplicate ``RgbColor`` while losing the canonical CSS form
everyone recognises. So hex stays a validated string wrapper.

``AbsolutePath`` is the unrelated filesystem-path primitive that has
always lived here; it stays a thin validated string.
"""

from __future__ import annotations

import re
from abc import ABC, abstractmethod
from typing import Self

from coloraide import Color
from pydantic import BaseModel, ConfigDict, Field, RootModel, field_validator


def _fmt_num(x: float) -> str:
    """Plain decimal, no scientific notation, trailing zeros trimmed."""
    if abs(x) < 1e-6:
        return "0"
    s = f"{x:.6f}"
    if "." in s:
        s = s.rstrip("0").rstrip(".")
    return s or "0"


class CssColor(BaseModel, ABC):
    """Shared parent for structured CSS colour primitives.

    Every structured subclass must implement:

    - ``to_aide()`` — lift this colour into a ``coloraide.Color`` for
      math (conversion, composition, contrast, etc.).
    - ``from_aide(c)`` — construct this format's representation of a
      coloraide colour (typically the result of math). Each subclass
      knows the target space (``oklch`` / ``hsl`` / ``srgb``) and does
      the conversion + clamping.
    - ``__str__`` — the canonical CSS form, so a colour interpolates
      into prompts, logs, and errors naturally.

    ``from_css`` is concrete — every CSS string parses through coloraide
    regardless of source format, so we route it through ``from_aide``.
    """

    model_config = ConfigDict(extra="forbid")

    @abstractmethod
    def to_aide(self) -> Color:
        """Lift into a ``coloraide.Color`` (subclass picks the space)."""

    @classmethod
    @abstractmethod
    def from_aide(cls, c: Color) -> Self:
        """Build from a ``coloraide.Color`` (subclass picks the space)."""

    @classmethod
    def from_css(cls, s: str) -> Self:
        """Parse any CSS colour string via coloraide.

        The source format doesn't matter — coloraide parses ``oklch(...)``,
        ``hsl(...)``, ``rgb(...)``, ``#hex``, named colours, etc. The
        result is converted into THIS class's representation via
        ``from_aide``.
        """
        return cls.from_aide(Color(s))


def _hue_or_zero(h: float | None) -> float:
    """Coalesce the hue coloraide reports for an achromatic colour into 0.

    Coloraide returns ``None`` (or ``NaN`` when emitted from the HSL
    space) for hue when chroma/saturation collapses to zero — both are
    "no meaningful hue". Our primitives require a real number in
    [0, 360]; 0 is the conventional achromatic anchor.
    """
    import math

    if h is None or (isinstance(h, float) and math.isnan(h)):
        return 0.0
    return h % 360.0


def _aide_alpha_or_none(c: Color) -> float | None:
    """Coloraide carries alpha as 1.0 when opaque; our wire convention
    is to elide the field. This is the single rule."""
    alpha = float(c["alpha"])
    return None if alpha >= 1.0 else alpha


def _aide_alpha_or_one(alpha: float | None) -> float:
    """Inverse of the above for the constructor's positional arg."""
    return alpha if alpha is not None else 1.0


class OklchColor(CssColor):
    """A CSS OKLCH colour, structured.

    Channel ranges mirror the CSS spec / coloraide's defaults:

    - ``l``: lightness, 0–1 (0 = black, 1 = white).
    - ``c``: chroma, 0–0.5 (CSS is unbounded-ish; we cap at 0.5 because
      anything beyond is well outside the sRGB gamut and our strict
      contract for background/text already caps at 0.04 anyway).
    - ``h``: hue angle in degrees, 0–360. CSS allows hue outside
      [0, 360); coloraide normalises into the band, and we follow.
    - ``alpha``: optional, 0–1. ``None`` means fully opaque.
    """

    l: float = Field(ge=0.0, le=1.0)
    c: float = Field(ge=0.0, le=0.5)
    h: float = Field(ge=0.0, le=360.0)
    alpha: float | None = Field(default=None, ge=0.0, le=1.0)

    def to_aide(self) -> Color:
        return Color("oklch", [self.l, self.c, self.h], _aide_alpha_or_one(self.alpha))

    @classmethod
    def from_aide(cls, c: Color) -> OklchColor:
        o = c.convert("oklch")
        return cls(
            l=min(1.0, max(0.0, o["lightness"])),
            c=min(0.5, max(0.0, o["chroma"])),
            h=_hue_or_zero(o["hue"]),
            alpha=_aide_alpha_or_none(o),
        )

    def __str__(self) -> str:
        body = f"oklch({_fmt_num(self.l * 100)}% {_fmt_num(self.c)} {_fmt_num(self.h)}"
        if self.alpha is not None:
            body += f" / {_fmt_num(self.alpha)}"
        return body + ")"


class HslColor(CssColor):
    """A CSS HSL colour, structured. Produced deterministically from
    ``OklchColor`` by the pipeline; the LLM never picks HSL directly.

    - ``h``: hue, 0–360 degrees.
    - ``s``: saturation, 0–100 (percent).
    - ``l``: lightness, 0–100 (percent).
    - ``alpha``: optional, 0–1.
    """

    h: float = Field(ge=0.0, le=360.0)
    s: float = Field(ge=0.0, le=100.0)
    l: float = Field(ge=0.0, le=100.0)
    alpha: float | None = Field(default=None, ge=0.0, le=1.0)

    def to_aide(self) -> Color:
        # Coloraide stores HSL saturation/lightness on the 0–1 scale
        # internally even though CSS uses 0–100%. Our struct mirrors CSS
        # (0–100); divide on the way in.
        return Color(
            "hsl",
            [self.h, self.s / 100.0, self.l / 100.0],
            _aide_alpha_or_one(self.alpha),
        )

    @classmethod
    def from_aide(cls, c: Color) -> HslColor:
        # Multiply back to 0–100 on the way out (see to_aide).
        o = c.convert("hsl")
        return cls(
            h=_hue_or_zero(o["hue"]),
            s=min(100.0, max(0.0, o["saturation"] * 100.0)),
            l=min(100.0, max(0.0, o["lightness"] * 100.0)),
            alpha=_aide_alpha_or_none(o),
        )

    def __str__(self) -> str:
        body = f"hsl({_fmt_num(self.h)} {_fmt_num(self.s)}% {_fmt_num(self.l)}%"
        if self.alpha is not None:
            body += f" / {_fmt_num(self.alpha)}"
        return body + ")"


class RgbColor(CssColor):
    """A CSS sRGB colour, structured. Produced deterministically from
    ``OklchColor`` by the pipeline.

    - ``r`` / ``g`` / ``b``: integer 0–255, gamma-encoded sRGB (what
      every consumer renders).
    - ``alpha``: optional, 0–1.
    """

    r: int = Field(ge=0, le=255)
    g: int = Field(ge=0, le=255)
    b: int = Field(ge=0, le=255)
    alpha: float | None = Field(default=None, ge=0.0, le=1.0)

    def to_aide(self) -> Color:
        return Color(
            "srgb",
            [self.r / 255.0, self.g / 255.0, self.b / 255.0],
            _aide_alpha_or_one(self.alpha),
        )

    @classmethod
    def from_aide(cls, c: Color) -> RgbColor:
        # Out-of-sRGB OKLCH colours need gamut-fit before rounding so the
        # integer channels stay legal.
        o = c.convert("srgb").fit()
        return cls(
            r=int(round(o["red"] * 255)),
            g=int(round(o["green"] * 255)),
            b=int(round(o["blue"] * 255)),
            alpha=_aide_alpha_or_none(o),
        )

    def __str__(self) -> str:
        body = f"rgb({self.r} {self.g} {self.b}"
        if self.alpha is not None:
            body += f" / {_fmt_num(self.alpha)}"
        return body + ")"


# #RRGGBB or #RRGGBBAA. Lowercase or uppercase, exactly 6 or 8 hex digits.
_HEX_PATTERN = re.compile(r"^#(?:[0-9a-f]{6}|[0-9a-f]{8})$", re.IGNORECASE)


class HexColor(RootModel[str]):
    """A CSS hex colour: ``#RRGGBB`` or ``#RRGGBBAA``.

    The deliberate string exception among the colour primitives — hex IS
    naturally a string and the canonical CSS form everyone recognises.
    Eight digits when alpha is non-full (matching the form coloraide
    emits). The 3-digit shorthand (``#RGB``) is intentionally NOT
    accepted — it round-trips to a different colour and we never
    produce one.

    Doesn't inherit from ``CssColor`` because that's a ``BaseModel`` and
    ``HexColor`` is a ``RootModel[str]``; the to_aide / from_aide helpers
    are duck-typed onto it for symmetry.
    """

    @field_validator("root")
    @classmethod
    def _is_hex(cls, v: str) -> str:
        if not _HEX_PATTERN.match(v):
            raise ValueError(
                "HexColor must be '#RRGGBB' or '#RRGGBBAA' "
                f"(6 or 8 hex digits); got {v!r}"
            )
        return v

    def to_aide(self) -> Color:
        return Color(self.root)

    @classmethod
    def from_aide(cls, c: Color) -> HexColor:
        return cls(c.convert("srgb").fit().to_string(hex=True))

    @classmethod
    def from_css(cls, s: str) -> HexColor:
        return cls.from_aide(Color(s))

    def __str__(self) -> str:
        return self.root


class AbsolutePath(RootModel[str]):
    """An absolute filesystem path. Serializes as the raw path string."""

    @field_validator("root")
    @classmethod
    def _is_absolute(cls, v: str) -> str:
        if not v.startswith("/"):
            raise ValueError(
                f"AbsolutePath must start with '/'; got {v!r}"
            )
        return v

    def __str__(self) -> str:
        return self.root
