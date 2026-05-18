"""The customizable slot types: `ColorSlot` and `ImageSlot`."""

from __future__ import annotations

import re

from pydantic import BaseModel, ConfigDict, Field, field_validator

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
    """A named image the pipeline will generate and write to disk.

    ``depends_on`` lists other image slot ids whose resolved outputs this
    image builds on (visual continuity / one image feeding another). The
    colour palette is always an implicit dependency and is never listed
    here. Empty by default, so existing app.yaml files validate unchanged.
    Cross-reference checks (ids exist, no self-dep, no dupes, not the
    reserved key) live on ``AppFormat``; cycle detection lives on the
    executor graph — a slot in isolation cannot see its siblings.
    """

    depends_on: list[str] = Field(default_factory=list)
