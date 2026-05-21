"""ColorOutput — the resolved value for one color slot.

The body is a ``ColorValue`` (composition) so every place that holds "a
colour" — base, derivations, palette entries — uses the exact same shape.
The derivations are a typed ``Derivations`` model on the Python side
(attribute access, no string-keyed dicts in code); on the wire it
serializes as a plain dict for the frontend to read as a map.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, field_validator

from schema.output.color_value import ColorValue
from schema.output.derivations import Derivations


class ColorOutput(BaseModel):
    """One resolved colour: its value (in every format), prose, and the
    deterministic derivations the client uses as-is."""

    model_config = ConfigDict(extra="forbid")

    color: ColorValue
    display_name: str  # evocative human label, e.g. "Warm Ash Cream"
    description: str  # purpose/usage prose for the colour
    derivations: Derivations

    @field_validator("display_name", "description")
    @classmethod
    def _non_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("ColorOutput text fields must be non-empty")
        return v
