"""ColorPalette — the colour output group: the light/dark target plus
every resolved colour slot.

This is both the colour module's return type and the ``color_set`` group
on ``Output``. ``mode`` is **required**: every run resolves to exactly
one of light/dark and an ``output.yaml`` without it is rejected — that
deliberate breaking change is what motivated wrapping the bare
``dict[str, ColorOutput]`` in a model. ``extra="ignore"`` (not the
package-wide ``forbid``), matching ``Output`` / ``ImageOutput``: this
group is read back from externally- or previously-produced
``output.yaml`` files and one carrying since-removed keys must still
validate (stale keys dropped, not rejected). The wrapper exists so a
future run-wide colour field is an additive change, never another
breaking reshape.
"""

from __future__ import annotations

import re

from pydantic import BaseModel, ConfigDict, field_validator

from schema.color_mode import ColorMode
from schema.output.color_output import ColorOutput
from schema.output.color_value import ColorValue

_ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")
# Palette keys are richer than slot ids: they also include the flattened
# per-slot derivation keys (e.g. ``primary_card``) and the shared surface
# keys (``card``, ``popup``, ``divider``). Same character class, same
# starts-with-letter rule.
_PALETTE_KEY_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")


class ColorPalette(BaseModel):
    """The resolved light/dark mode, every colour slot, and the flat
    recommendation palette derived from them."""

    model_config = ConfigDict(extra="ignore")

    mode: ColorMode
    colors: dict[str, ColorOutput]
    palette: dict[str, ColorValue]

    @field_validator("colors")
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

    @field_validator("palette")
    @classmethod
    def _palette_keys_snake_case(
        cls, v: dict[str, object]
    ) -> dict[str, object]:
        for key in v:
            if not _PALETTE_KEY_PATTERN.match(key):
                raise ValueError(
                    f"palette key {key!r} must be snake_case "
                    "(lowercase, digits, underscores; must start with a "
                    "letter)"
                )
        return v
