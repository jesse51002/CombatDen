"""TextSet — the text output group: every resolved text slot keyed by id.

The text module's return type and the ``text_set`` group on ``Output``.
``extra="ignore"`` matches ``ColorPalette`` / ``ImageSet`` / ``FontSet``:
this group is read back from externally- or previously-produced
``output.yaml`` files and one carrying since-removed keys must still
validate. The wrapper exists so a future run-wide text field (a target
locale, a voice tag) is an additive change, never another breaking
reshape.

An empty ``texts`` dict carries two collapsed-but-equivalent meanings:
the app declared no text slots, OR every text slot failed its
length-bound validation loop. The MobileApp falls back to its own
default copy in either case, so the consumer doesn't need to tell them
apart.
"""

from __future__ import annotations

import re

from pydantic import BaseModel, ConfigDict, Field, field_validator

from schema.output.text_output import TextOutput

_ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")


class TextSet(BaseModel):
    """Every resolved text slot, keyed by snake_case slot id."""

    model_config = ConfigDict(extra="ignore")

    texts: dict[str, TextOutput] = Field(default_factory=dict)

    @field_validator("texts")
    @classmethod
    def _slot_ids_snake_case(
        cls, v: dict[str, object]
    ) -> dict[str, object]:
        for slot_id in v:
            if not _ID_PATTERN.match(slot_id):
                raise ValueError(
                    f"text slot id {slot_id!r} must be snake_case "
                    "(lowercase, digits, underscores; must start with a "
                    "letter)"
                )
        return v
