"""AppFormat — the shape of an app's `app.yaml` slot manifest."""

from __future__ import annotations

import re

from pydantic import BaseModel, ConfigDict, field_validator, model_validator

from schema.color_role import ColorRole
from schema.slots import ColorSlot, ImageSlot

_ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")


class AppFormat(BaseModel):
    """Slot inventory for one app. One YAML document per app."""

    model_config = ConfigDict(extra="forbid")

    id: str
    display_name: str
    images: list[ImageSlot]
    colors: list[ColorSlot]

    @field_validator("id")
    @classmethod
    def _id_is_snake_case(cls, v: str) -> str:
        if not _ID_PATTERN.match(v):
            raise ValueError(
                f"app id {v!r} must be snake_case "
                "(lowercase, digits, underscores; must start with a letter)"
            )
        return v

    @field_validator("display_name")
    @classmethod
    def _display_name_non_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("display_name must be non-empty")
        return v

    @model_validator(mode="after")
    def _slot_lists_well_formed(self) -> "AppFormat":
        if not self.images:
            raise ValueError("AppFormat.images must contain at least one slot")
        if not self.colors:
            raise ValueError("AppFormat.colors must contain at least one slot")

        image_ids = [s.id for s in self.images]
        if len(image_ids) != len(set(image_ids)):
            dupes = sorted({i for i in image_ids if image_ids.count(i) > 1})
            raise ValueError(f"duplicate image slot ids: {dupes}")

        color_ids = [s.id for s in self.colors]
        if len(color_ids) != len(set(color_ids)):
            dupes = sorted({i for i in color_ids if color_ids.count(i) > 1})
            raise ValueError(f"duplicate color slot ids: {dupes}")

        # Exactly one background + one text slot: the deterministic contrast
        # check pairs these two. Enforced at config load, before any LLM call.
        roles = [s.role for s in self.colors]
        n_bg = roles.count(ColorRole.BACKGROUND)
        if n_bg != 1:
            raise ValueError(
                "AppFormat.colors must have exactly one slot with "
                f"role 'background'; found {n_bg}"
            )
        n_text = roles.count(ColorRole.TEXT)
        if n_text != 1:
            raise ValueError(
                "AppFormat.colors must have exactly one slot with "
                f"role 'text'; found {n_text}"
            )

        return self
