"""IconSet — the icon output group: every resolved icon slot keyed by id.

The icon module's return type and the ``icon_set`` group on ``Output``.
``extra="ignore"`` matches ``FontSet`` / ``ImageSet``: this group is read
back from previously-produced ``output.yaml`` files and one carrying
since-removed keys must still validate. The wrapper exists so a future
run-wide icon field (a chosen-set summary, a stroke-weight default) is an
additive change, never another breaking reshape.

Not to be confused with the *catalog* concept "icon set" (the curated
source library): that is ``IconSetCatalogEntry`` /
``IconSetCatalog`` under ``src/shared/``. This is the produced output
group only.
"""

from __future__ import annotations

import re

from pydantic import BaseModel, ConfigDict, Field, field_validator

from schema.output.icon_output import IconOutput

_ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")


class IconSet(BaseModel):
    """Every resolved icon slot, keyed by snake_case slot id."""

    model_config = ConfigDict(extra="ignore")

    icons: dict[str, IconOutput] = Field(default_factory=dict)

    @field_validator("icons")
    @classmethod
    def _slot_ids_snake_case(
        cls, v: dict[str, object]
    ) -> dict[str, object]:
        for slot_id in v:
            if not _ID_PATTERN.match(slot_id):
                raise ValueError(
                    f"icon slot id {slot_id!r} must be snake_case "
                    "(lowercase, digits, underscores; must start with a "
                    "letter)"
                )
        return v
