"""FontSet — the font output group: every resolved font slot keyed by id.

The font module's return type and the ``font_set`` group on ``Output``.
``extra="ignore"`` matches ``ColorPalette`` / ``ImageSet``: this group
is read back from externally- or previously-produced ``output.yaml``
files and one carrying since-removed keys must still validate. The
wrapper exists so a future run-wide font field (a target language /
script, a default fallback chain) is an additive change, never another
breaking reshape.
"""

from __future__ import annotations

import re

from pydantic import BaseModel, ConfigDict, field_validator

from schema.output.font_output import FontOutput

_ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")


class FontSet(BaseModel):
    """Every resolved font slot, keyed by snake_case slot id."""

    model_config = ConfigDict(extra="ignore")

    fonts: dict[str, FontOutput]

    @field_validator("fonts")
    @classmethod
    def _slot_ids_snake_case(
        cls, v: dict[str, object]
    ) -> dict[str, object]:
        for slot_id in v:
            if not _ID_PATTERN.match(slot_id):
                raise ValueError(
                    f"font slot id {slot_id!r} must be snake_case "
                    "(lowercase, digits, underscores; must start with a "
                    "letter)"
                )
        return v
