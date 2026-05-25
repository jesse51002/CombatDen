"""The global, app-agnostic Lottie preset catalog.

A hand-curated library of animation presets that the lottie module
selects from — the Lottie analog of the Google Fonts catalog the font
module picks against. Files live under ``assets/lottie_animations/``;
``index.yaml`` there validates against ``LottieLibrary``.

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


class RecolorRegion(BaseModel):
    """One color-bearing region of an animation the recolor step tints.

    ``name`` is the literal layer name in the Lottie file (snake_case);
    ``description`` says what that color *does* in the animation — the core
    fill, an outer ring, an edge stroke, an ambient field — so the recolor
    LLM can map it to the right palette role on purpose rather than guessing
    from an opaque layer name.
    """

    model_config = ConfigDict(extra="forbid")

    name: str
    description: str

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
    # Library-relative path to the .lottie/.json file, e.g.
    # ``pulse_ring.json`` (resolved against the library root by the
    # loader / the consuming app).
    file: str
    types: list[LottieType]
    recolor_regions: list[RecolorRegion]
    # Required iff ``REVEAL`` is among ``types`` (enforced below). A
    # standalone-only preset leaves it unset.
    insertion_point: InsertionPoint | None = None

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


class LottieLibrary(BaseModel):
    """The whole catalog: every curated preset, with unique ids."""

    model_config = ConfigDict(extra="forbid")

    presets: list[LottiePreset]

    @field_validator("presets")
    @classmethod
    def _unique_preset_ids(
        cls, v: list[LottiePreset]
    ) -> list[LottiePreset]:
        ids = [p.id for p in v]
        if len(ids) != len(set(ids)):
            dupes = sorted({i for i in ids if ids.count(i) > 1})
            raise ValueError(f"duplicate preset ids: {dupes}")
        return v
