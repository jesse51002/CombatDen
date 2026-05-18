"""The customizable slot types: `ColorSlot` and `ImageSlot`."""

from __future__ import annotations

import re

from pydantic import BaseModel, ConfigDict, field_validator

from schema.color_role import ColorRole

_ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")


class SlotBase(BaseModel):
    """Shared shape for every customizable slot."""

    model_config = ConfigDict(extra="forbid")

    id: str
    description: str

    @field_validator("id")
    @classmethod
    def _id_is_snake_case(cls, v: str) -> str:
        if not _ID_PATTERN.match(v):
            raise ValueError(
                f"slot id {v!r} must be snake_case "
                "(lowercase, digits, underscores; must start with a letter)"
            )
        return v

    @field_validator("description")
    @classmethod
    def _description_non_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("slot description must be non-empty")
        return v


class ColorSlot(SlotBase):
    """A named color the pipeline will resolve to an oklch value.

    ``role`` is optional and validation-only: it is never sent to the LLM
    (the prompt infers role from the description). When set, it tells the
    deterministic contract which colours to contrast-test and sanity-bound.
    """

    role: ColorRole | None = None


class ImageSlot(SlotBase):
    """A named image the pipeline will generate and write to disk."""
