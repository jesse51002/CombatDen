"""The global, app-agnostic Lottie preset catalog.

A hand-curated library of animation presets that the lottie module
selects from — the Lottie analog of the Google Fonts catalog the font
module picks against. Each preset is its own folder under
``assets/lottie_animations/<preset_id>/`` holding a ``config.yaml`` (this
model) beside the animation ``.json``; the loader scans the folders, so a
``LottiePreset`` is validated directly per file (there is no list wrapper —
the way ``IconSetCatalogEntry`` is one-per-``set.yaml``).

The catalog is an INPUT contract, so it keeps the package-wide
``extra="forbid"`` (a typo in a preset entry must fail loudly), unlike
the produced ``output.yaml`` read-models.
"""

from __future__ import annotations

import re

from pydantic import BaseModel, ConfigDict, field_validator, model_validator

from schema.lottie_type import LottieType

_ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")


class InsertionPoint(BaseModel):
    """Where a reveal preset composites the revealed image.

    Normalized to the animation's composition box: ``x``/``y`` is the
    anchor (0..1, top-left origin) and ``width``/``height`` the size
    (0..1). ``frame`` is the timeline frame the image appears at. The
    consuming Flutter app reads these to place the revealed image inside
    the playing animation.
    """

    model_config = ConfigDict(extra="forbid")

    frame: int
    x: float
    y: float
    width: float
    height: float
    # Reveal dwell: after the image appears, it (and the animation) hold for
    # this many seconds, then both end — the playing animation is cut short
    # if it has not finished. Reveal-only, which is why it lives on the
    # insertion point (a standalone preset has neither).
    hold_seconds: float

    @field_validator("hold_seconds")
    @classmethod
    def _hold_seconds_positive(cls, v: float) -> float:
        if v <= 0:
            raise ValueError(
                f"InsertionPoint.hold_seconds must be > 0; got {v!r}"
            )
        return v


class RecolorRegion(BaseModel):
    """One color-bearing region of an animation the recolor step tints.

    ``name`` is a snake_case region id (what the recolor LLM maps to a
    palette role); ``description`` says what that color *does* in the
    animation — the core fill, an outer ring, an edge stroke, an ambient
    field — so the recolor LLM can map it to the right palette role on
    purpose rather than guessing. ``layers`` is the set of **literal Lottie
    layer names** (the ``nm`` strings, verbatim — NOT snake_case) whose
    colours belong to this region; the bake step recolours every solid /
    gradient fill and stroke on exactly those layers. It is required and
    non-empty: without it the bake would not know which layers to touch.
    """

    model_config = ConfigDict(extra="forbid")

    name: str
    description: str
    layers: list[str]

    @field_validator("name")
    @classmethod
    def _name_is_snake_case(cls, v: str) -> str:
        if not _ID_PATTERN.match(v):
            raise ValueError(
                f"recolor region {v!r} must be snake_case "
                "(lowercase, digits, underscores; must start with a letter)"
            )
        return v

    @field_validator("description")
    @classmethod
    def _description_non_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("RecolorRegion.description must be non-empty")
        return v

    @field_validator("layers")
    @classmethod
    def _layers_non_empty(cls, v: list[str]) -> list[str]:
        # Literal layer names, kept verbatim (Lottie ``nm`` strings can be
        # any case / spacing) — only emptiness is rejected, not their shape.
        if not v or any(not name.strip() for name in v):
            raise ValueError(
                "RecolorRegion.layers must list at least one non-empty "
                "layer name"
            )
        return v


class LottiePreset(BaseModel):
    """One curated animation in the global library.

    ``types`` is a list because a single preset can serve as both a
    ``standalone`` and a ``reveal`` animation. ``recolor_regions`` names
    the parts of the animation the pipeline maps to palette roles, each with
    a description of what that color does that is fed to the recolor prompt;
    the recolor LLM call assigns each region a palette key. A reveal-capable
    preset must declare its single ``insertion_point``.
    """

    model_config = ConfigDict(extra="forbid")

    id: str
    display_name: str
    description: str
    # Animation ``.json`` filename, resolved against the preset's OWN folder
    # (``<library_root>/<id>/<file>``) by the loader — e.g. ``pulse_ring.json``,
    # not a library-relative path.
    file: str
    types: list[LottieType]
    # Playback multiplier the app applies to the animation duration (2.0 =>
    # plays in half the time). Lifted onto the output and the wire.
    speed: float = 1.0
    recolor_regions: list[RecolorRegion]
    # Required iff ``REVEAL`` is among ``types`` (enforced below). A
    # standalone-only preset leaves it unset.
    insertion_point: InsertionPoint | None = None

    @field_validator("speed")
    @classmethod
    def _speed_positive(cls, v: float) -> float:
        if v <= 0:
            raise ValueError(f"LottiePreset.speed must be > 0; got {v!r}")
        return v

    @field_validator("id")
    @classmethod
    def _id_is_snake_case(cls, v: str) -> str:
        if not _ID_PATTERN.match(v):
            raise ValueError(
                f"preset id {v!r} must be snake_case "
                "(lowercase, digits, underscores; must start with a letter)"
            )
        return v

    @field_validator("display_name", "description", "file")
    @classmethod
    def _non_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("LottiePreset field must be non-empty")
        return v

    @field_validator("types")
    @classmethod
    def _types_non_empty_unique(
        cls, v: list[LottieType]
    ) -> list[LottieType]:
        if not v:
            raise ValueError("LottiePreset.types must list at least one type")
        if len(v) != len(set(v)):
            raise ValueError(f"LottiePreset.types has duplicates: {v}")
        return v

    @field_validator("recolor_regions")
    @classmethod
    def _regions_non_empty_unique(
        cls, v: list[RecolorRegion]
    ) -> list[RecolorRegion]:
        # Per-name snake_case + non-empty description are enforced on
        # ``RecolorRegion`` itself; here we only guard the list as a whole.
        if not v:
            raise ValueError(
                "LottiePreset.recolor_regions must list at least one region"
            )
        names = [r.name for r in v]
        if len(names) != len(set(names)):
            dupes = sorted({n for n in names if names.count(n) > 1})
            raise ValueError(f"duplicate recolor_regions: {dupes}")
        return v

    @model_validator(mode="after")
    def _reveal_has_insertion_point(self) -> "LottiePreset":
        # A reveal-capable preset has to say where the revealed image
        # lands; a standalone-only preset must not carry a stray point.
        # FUTURE: a per-region or per-preset ``no_recolor`` flag could
        # mark regions the recolor step must leave untouched (brand-locked
        # colours, or very colourful animations the palette would clash
        # with). Not implemented now — every listed region is recolorable.
        if LottieType.REVEAL in self.types and self.insertion_point is None:
            raise ValueError(
                f"reveal-capable preset {self.id!r} must declare an "
                "insertion_point"
            )
        if LottieType.REVEAL not in self.types and self.insertion_point is not None:
            raise ValueError(
                f"standalone-only preset {self.id!r} must not declare an "
                "insertion_point"
            )
        return self
