"""FormatSet — the format output group: every resolved format slot by id.

The format module's return type and the ``format_set`` group on
``Output``. ``extra="ignore"`` matches ``TextSet`` / ``IconSet`` /
``FontSet``: this group is read back from previously-produced
``output.yaml`` files and one carrying since-removed keys must still
validate. The wrapper exists so a future run-wide format field is an
additive change, never another breaking reshape.

One named choice per declared surface is a **collection of resolved
items**, which is exactly what ``CLAUDE.md`` → *Output groups* says gets
its own model under a ``*_set`` key — not a run-wide scalar like
``category``, which is one value and therefore a plain field on
``Output``.

An empty ``formats`` dict carries two collapsed-but-equivalent meanings:
the app declared no format slots, OR the format node failed. The
consuming client renders the arrangement it ships by default in either
case, so it doesn't need to tell them apart — the same collapse
``TextSet`` makes.
"""

from __future__ import annotations

import re

from pydantic import BaseModel, ConfigDict, Field, field_validator

from schema.output.format_output import FormatOutput

_ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")


class FormatSet(BaseModel):
    """Every resolved format slot, keyed by snake_case slot id."""

    model_config = ConfigDict(extra="ignore")

    formats: dict[str, FormatOutput] = Field(default_factory=dict)

    @field_validator("formats")
    @classmethod
    def _slot_ids_snake_case(
        cls, v: dict[str, object]
    ) -> dict[str, object]:
        for slot_id in v:
            if not _ID_PATTERN.match(slot_id):
                raise ValueError(
                    f"format slot id {slot_id!r} must be snake_case "
                    "(lowercase, digits, underscores; must start with a "
                    "letter)"
                )
        return v
