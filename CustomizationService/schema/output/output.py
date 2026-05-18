"""Output — the shape of the produced `output.yaml` artifact."""

from __future__ import annotations

import re

from pydantic import BaseModel, ConfigDict, field_validator

from schema.output.color_output import ColorOutput
from schema.output.image_output import ImageOutput
from schema.output.run_cost import RunCost

_ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")


class Output(BaseModel):
    """Resolved customization for one app. One YAML document per pipeline run.

    ``cost`` is optional, like ``ImageOutput.complexity``: every fresh run
    sets it, but older or externally-produced ``output.yaml`` files
    predate the field and must still validate (defaults to ``None``)."""

    model_config = ConfigDict(extra="forbid")

    app: str
    display_name: str
    images: dict[str, ImageOutput]
    colors: dict[str, ColorOutput]
    cost: RunCost | None = None

    @field_validator("app")
    @classmethod
    def _app_id_snake_case(cls, v: str) -> str:
        if not _ID_PATTERN.match(v):
            raise ValueError(
                f"app {v!r} must be snake_case "
                "(lowercase, digits, underscores; must start with a letter)"
            )
        return v

    @field_validator("display_name")
    @classmethod
    def _display_name_non_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("display_name must be non-empty")
        return v

    @field_validator("images", "colors")
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
