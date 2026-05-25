"""AppFormat — the shape of an app's `app.yaml` slot manifest."""

from __future__ import annotations

import re

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from schema.color_role import ColorRole
from schema.lottie_type import LottieType
from schema.slots import (
    ColorSlot,
    FontSlot,
    IconSlot,
    ImageSlot,
    LottieSlot,
    TextSlot,
)

_ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")

# Image slot ids that collide with an executor-injected dependency key are
# rejected: a node's resolved-input dict is keyed by these, so an image
# named "color" would shadow the palette. Source of truth for the values
# is ``src.modules.base.DependencyKind`` (kept local so schema/ imports no
# src/ — same reason ColorRole lives in schema/). ``font``, ``text`` and
# ``icon`` are reserved for the same keyspace reason even though no image
# module depends on any of them today, so a future ``depends_on: font`` /
# ``depends_on: text`` / ``depends_on: icon`` doesn't get shadowed.
_EXECUTOR_NODE_NAMES = frozenset({"color", "font", "text", "icon"})


def _assert_unique_ids(slots: list, *, kind: str) -> None:
    """Shared id-uniqueness check across every slot list. ``kind`` is
    the human-readable noun ("image", "color", ...) used in the error
    message — the four slot lists all need the same check and the only
    thing that varies between them is what to call the slot in the
    raised ``ValueError``."""
    ids = [s.id for s in slots]
    if len(ids) != len(set(ids)):
        dupes = sorted({i for i in ids if ids.count(i) > 1})
        raise ValueError(f"duplicate {kind} slot ids: {dupes}")


class AppFormat(BaseModel):
    """Slot inventory for one app. One YAML document per app."""

    model_config = ConfigDict(extra="forbid")

    id: str
    display_name: str
    images: list[ImageSlot] = Field(default_factory=list)
    colors: list[ColorSlot] = Field(default_factory=list)
    fonts: list[FontSlot] = Field(default_factory=list)
    texts: list[TextSlot] = Field(default_factory=list)
    icons: list[IconSlot] = Field(default_factory=list)
    lotties: list[LottieSlot] = Field(default_factory=list)

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

    @field_validator("images")
    @classmethod
    def _images_well_formed(
        cls, v: list[ImageSlot]
    ) -> list[ImageSlot]:
        """Image-only invariants: unique ids, no shadowing of an
        executor-injected dependency key, and well-formed ``depends_on``
        cross-references. Cycle detection is the executor graph's job
        (it owns the edge set) — a slot in isolation cannot see its
        siblings beyond this single field's list.
        """
        _assert_unique_ids(v, kind="image")

        ids = [s.id for s in v]
        reserved = sorted(set(ids) & _EXECUTOR_NODE_NAMES)
        if reserved:
            raise ValueError(
                f"image slot ids {reserved} are reserved executor "
                "dependency keys (see src.modules.base.DependencyKind)"
            )

        id_set = set(ids)
        for s in v:
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
            unknown = sorted(set(s.depends_on) - id_set)
            if unknown:
                raise ValueError(
                    f"image slot {s.id!r} depends_on unknown image ids: "
                    f"{unknown}"
                )
        return v

    @field_validator("colors")
    @classmethod
    def _colors_well_formed(
        cls, v: list[ColorSlot]
    ) -> list[ColorSlot]:
        """Colour-only invariants: unique ids, plus exactly one
        ``background`` role and exactly one ``text`` role when the
        list is non-empty — the deterministic contrast check pairs
        those two and won't run without them. An empty colours list
        is allowed (and skips the role check) so a minimal/partial
        app definition still validates; production apps always
        declare both."""
        _assert_unique_ids(v, kind="color")
        if not v:
            return v

        roles = [s.role for s in v]
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
        return v

    @field_validator("fonts")
    @classmethod
    def _fonts_well_formed(cls, v: list[FontSlot]) -> list[FontSlot]:
        """Font-only invariants: unique ids. The font module keys
        its per-request closed LLM response model by these ids, so a
        collision would silently overwrite a slot."""
        _assert_unique_ids(v, kind="font")
        return v

    @field_validator("texts")
    @classmethod
    def _texts_well_formed(cls, v: list[TextSlot]) -> list[TextSlot]:
        """Text-only invariants: unique ids. Same reason as fonts —
        the text module's per-request closed response model is keyed
        by slot id."""
        _assert_unique_ids(v, kind="text")
        return v

    @field_validator("icons")
    @classmethod
    def _icons_well_formed(cls, v: list[IconSlot]) -> list[IconSlot]:
        """Icon-only invariants: unique ids. Same reason as fonts —
        the icon module's per-request closed matching/prompt response
        models are keyed by slot id, so a collision would silently
        overwrite a slot."""
        _assert_unique_ids(v, kind="icon")
        return v

    @field_validator("lotties")
    @classmethod
    def _lotties_well_formed(
        cls, v: list[LottieSlot]
    ) -> list[LottieSlot]:
        """Lottie-only invariants visible within this single field:
        unique ids and no shadowing of an executor-injected dependency
        key (each lottie slot becomes a graph node keyed by its id, so a
        slot named ``color`` would shadow the palette in its own inputs
        dict — exactly the image-slot rule). The reveal -> image
        ``depends_on`` cross-reference and the lottie/image id disjointness
        need the other slot lists, so they live on the model validator
        below."""
        _assert_unique_ids(v, kind="lottie")

        ids = [s.id for s in v]
        reserved = sorted(set(ids) & _EXECUTOR_NODE_NAMES)
        if reserved:
            raise ValueError(
                f"lottie slot ids {reserved} are reserved executor "
                "dependency keys (see src.modules.base.DependencyKind)"
            )
        return v

    @model_validator(mode="after")
    def _lottie_reveal_refs(self) -> "AppFormat":
        """Cross-list lottie checks that a single-field validator can't
        do (it only sees its own list):

        - every reveal lottie slot's ``depends_on`` must name a real
          image slot id (the executor injects that image's resolved
          output into the reveal node);
        - lottie slot ids must be disjoint from image slot ids, because
          both become graph node keys — two nodes sharing a ``key`` would
          collide in the executor.
        """
        image_ids = {i.id for i in self.images}
        lottie_ids = {s.id for s in self.lotties}

        clash = sorted(image_ids & lottie_ids)
        if clash:
            raise ValueError(
                f"lottie slot ids {clash} collide with image slot ids "
                "(both become graph node keys and must be unique)"
            )

        for slot in self.lotties:
            if slot.depends_on is not None and slot.depends_on not in image_ids:
                raise ValueError(
                    f"reveal lottie slot {slot.id!r} depends_on unknown "
                    f"image id {slot.depends_on!r}"
                )
        return self
