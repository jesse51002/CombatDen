"""AppFormat — the shape of an app's `app.yaml` slot manifest."""

from __future__ import annotations

import re

from pydantic import BaseModel, ConfigDict, field_validator, model_validator

from schema.color_role import ColorRole
from schema.slots import ColorSlot, ImageSlot

_ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")

# Image slot ids that collide with an executor-injected dependency key are
# rejected: a node's resolved-input dict is keyed by these, so an image
# named "color" would shadow the palette. Source of truth for the values
# is ``src.modules.base.DependencyKind`` (kept local so schema/ imports no
# src/ — same reason ColorRole lives in schema/).
_RESERVED_IMAGE_IDS = frozenset({"color"})


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

        reserved = sorted(set(image_ids) & _RESERVED_IMAGE_IDS)
        if reserved:
            raise ValueError(
                f"image slot ids {reserved} are reserved executor "
                "dependency keys (see src.modules.base.DependencyKind)"
            )

        # depends_on cross-references: every id must be a declared image
        # slot, no self-dependency, no dupes within one slot's list. Cycle
        # detection is the executor graph's job (it owns the edge set).
        image_id_set = set(image_ids)
        for s in self.images:
            if s.id in s.depends_on:
                raise ValueError(
                    f"image slot {s.id!r} cannot depend on itself"
                )
            if len(s.depends_on) != len(set(s.depends_on)):
                d = sorted(
                    {i for i in s.depends_on if s.depends_on.count(i) > 1}
                )
                raise ValueError(
                    f"image slot {s.id!r} has duplicate depends_on ids: {d}"
                )
            unknown = sorted(set(s.depends_on) - image_id_set)
            if unknown:
                raise ValueError(
                    f"image slot {s.id!r} depends_on unknown image ids: "
                    f"{unknown}"
                )

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
