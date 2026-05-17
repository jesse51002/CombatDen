"""ColorOutput — the resolved value for one color slot."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, field_validator

from schema.primitives import HexColor


class ColorOutput(BaseModel):
    """One resolved colour: the hex plus why it is what it is."""

    model_config = ConfigDict(extra="forbid")

    hex: HexColor
    description: str  # natural-language description of the colour itself
    vibe: str  # the feeling/mood it carries

    @field_validator("description", "vibe")
    @classmethod
    def _non_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("ColorOutput text fields must be non-empty")
        return v
