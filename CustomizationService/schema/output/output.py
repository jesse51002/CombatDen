"""Output — the shape of the produced `output.yaml` artifact."""

from __future__ import annotations

import re

from pydantic import BaseModel, ConfigDict, field_validator

from schema.output.color_palette import ColorPalette
from schema.output.image_set import ImageSet
from schema.output.run_cost import RunCost

_ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")


class Output(BaseModel):
    """Resolved customization for one app. One YAML document per pipeline run.

    Each output group is its own model, never a bare ``dict``:
    ``image_set`` (``ImageSet``) and ``color_set`` (``ColorPalette``,
    which also carries the required light/dark ``mode``). The wrappers
    exist so a group can gain run-wide fields without another breaking
    ``output.yaml`` reshape.

    ``cost`` is optional, like ``ImageOutput.complexity``: every fresh run
    sets it, but older or externally-produced ``output.yaml`` files
    predate the field and must still validate (defaults to ``None``).
    ``extra="ignore"`` (not the package-wide ``forbid``) is a deliberate
    exception, matching ``ImageOutput`` / ``ColorPalette`` / ``ImageSet``:
    an externally- or previously-produced ``output.yaml`` carrying
    now-removed keys still validates, the stale keys silently dropped."""

    model_config = ConfigDict(extra="ignore")

    app: str
    display_name: str
    image_set: ImageSet
    color_set: ColorPalette
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
