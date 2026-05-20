"""ImageSet — the image output group: every resolved image slot.

The ``image_set`` group on ``Output``. Only ``images`` today; it is a
forward-compat wrapper so future run-wide image metadata is an additive
change, never a breaking ``output.yaml`` reshape (the same reason
``ColorPalette`` wraps its colours). ``extra="ignore"`` matches
``Output`` / ``ImageOutput``: read back from externally- or
previously-produced ``output.yaml`` files, since-removed keys dropped.
"""

from __future__ import annotations

import re

from pydantic import BaseModel, ConfigDict, field_validator

from schema.output.image_output import ImageOutput

_ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")


class ImageSet(BaseModel):
    """Every resolved image slot, keyed by slot id."""

    model_config = ConfigDict(extra="ignore")

    images: dict[str, ImageOutput]

    @field_validator("images")
    @classmethod
    def _slot_ids_snake_case(
        cls, v: dict[str, object]
    ) -> dict[str, object]:
        for slot_id in v:
            if not _ID_PATTERN.match(slot_id):
                raise ValueError(
                    f"slot id {slot_id!r} must be snake_case "
                    "(lowercase, digits, underscores; must start with a "
                    "letter)"
                )
        return v
