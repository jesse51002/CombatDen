"""Output — the shape of the produced `output.yaml` artifact."""

from __future__ import annotations

import re

from pydantic import BaseModel, ConfigDict, Field, field_validator

from schema.output.color_palette import ColorPalette
from schema.output.font_set import FontSet
from schema.output.format_set import FormatSet
from schema.output.icon_set import IconSet
from schema.output.image_set import ImageSet
from schema.output.run_cost import RunCost
from schema.output.text_set import TextSet

_ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")


class Output(BaseModel):
    """Resolved customization for one app. One YAML document per pipeline run.

    ``display_name`` is the app/brand name (from ``app.yaml``);
    ``design_name`` is this run's design/style name (from the input
    ``customization.yaml``'s ``design_direction.name``) — the label a
    style picker shows to distinguish one preset from another.

    Each output group is its own model, never a bare ``dict``:
    ``image_set`` (``ImageSet``), ``color_set`` (``ColorPalette``, which
    also carries the required light/dark ``mode``), and ``font_set``
    (``FontSet``). The wrappers exist so a group can gain run-wide
    fields without another breaking ``output.yaml`` reshape.

    ``category`` is this run's classification bucket — one of the values
    the app declares under ``categories`` in its ``app.yaml`` (the code
    is app-agnostic: it supports "classification", the class values are
    the app's own). It is produced by the pipeline's classification node
    (``src/modules/categories/``) and validated against that declared
    vocabulary before the ``Writer`` dumps it. The style picker REQUIRES
    it (an uncategorised run is never listed by
    ``GET /apps/{id}/styles``), but the field is ``None``-able here so
    runs that predate it — and runs of apps with no classification
    concept — still validate. It is a bare string on the wire, not a
    group: a classification is one value, and every consumer (the styles
    API, both client runtimes, the FastApi backend) reads it that way.

    ``cost`` is optional, like ``ImageOutput.complexity``: every fresh run
    sets it, but older or externally-produced ``output.yaml`` files
    predate the field and must still validate (defaults to ``None``).
    ``font_set`` follows the same backward-compatibility shape — every
    fresh run sets it, older files predate it and default to an empty
    ``FontSet(fonts={})``. ``text_set`` does the same — older files
    predate it and default to an empty ``TextSet()`` (no copy
    overrides). An empty ``text_set.texts`` is also the honest answer
    when the app declared no text slots, so the MobileApp's fallback
    path (use the bundled default string) is one branch, not two.
    ``icon_set`` follows the same shape — every fresh run sets it, older
    files predate it and default to an empty ``IconSet()`` (no icon
    overrides; the app falls back to its bundled icons). ``format_set``
    does the same — older files predate it and default to an empty
    ``FormatSet()``, which is also the honest answer when the app declared
    no format slots; the client then renders the arrangement it ships.
    It is a *group*, not a scalar like ``category``, because it holds one
    resolved item per declared format slot.

    ``extra="ignore"`` (not the package-wide ``forbid``) is a deliberate
    exception, matching ``ImageOutput`` / ``ColorPalette`` / ``ImageSet``:
    an externally- or previously-produced ``output.yaml`` carrying
    now-removed keys still validates, the stale keys silently dropped."""

    model_config = ConfigDict(extra="ignore")

    app: str
    display_name: str
    design_name: str
    category: str | None = None
    image_set: ImageSet
    color_set: ColorPalette
    font_set: FontSet = Field(default_factory=lambda: FontSet(fonts={}))
    text_set: TextSet = Field(default_factory=TextSet)
    icon_set: IconSet = Field(default_factory=IconSet)
    format_set: FormatSet = Field(default_factory=FormatSet)
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

    @field_validator("display_name", "design_name")
    @classmethod
    def _name_non_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("name must be non-empty")
        return v
