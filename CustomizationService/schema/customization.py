"""Customization — the shape of a run's `customization.yaml` brand brief."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, field_validator

from schema.color_mode import ColorMode


class DesignDirection(BaseModel):
    """Brand intent prose fed into every agent prompt."""

    model_config = ConfigDict(extra="forbid")

    name: str
    short_desc: str
    long_desc: str

    @field_validator("name", "short_desc", "long_desc")
    @classmethod
    def _non_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("field must be non-empty")
        return v


class ColorsDirection(BaseModel):
    """Raw color brief: prose intent plus the light/dark mode."""

    model_config = ConfigDict(extra="forbid")

    description: str
    mode: ColorMode

    @field_validator("description")
    @classmethod
    def _description_non_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("colors_direction.description must be non-empty")
        return v


class Customization(BaseModel):
    """User-edited brief. One YAML document per pipeline run."""

    model_config = ConfigDict(extra="forbid")

    design_direction: DesignDirection
    colors_direction: ColorsDirection
