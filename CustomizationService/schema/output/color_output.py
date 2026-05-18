"""ColorOutput — the resolved value for one color slot."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, field_validator

from schema.primitives import OklchColor


class ColorOutput(BaseModel):
    """One resolved colour: the oklch value plus its name and rationale."""

    model_config = ConfigDict(extra="forbid")

    oklch: OklchColor
    display_name: str  # evocative human label, e.g. "Warm Ash Cream"
    description: str  # purpose/usage prose for the colour

    @field_validator("display_name", "description")
    @classmethod
    def _non_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("ColorOutput text fields must be non-empty")
        return v
