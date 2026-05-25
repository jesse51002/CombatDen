"""LottieOutput — one resolved lottie slot in the produced ``output.yaml``.

The selection LLM picks a preset; the recolour LLM maps each of that
preset's regions to a palette role. The trusted fields — ``preset_file``,
``display_name``, ``insertion_point`` — are lifted off the library preset
metadata after the pick, never asked of the LLM, so they cannot drift
(the same discipline ``FontOutput.category`` follows).

``region_roles`` stores only role NAME references (palette keys), never
resolved colour values: the Flutter app recolours at render time against
its own live palette, so a brand whose palette later shifts re-tints the
animation for free.

``reveals`` and ``insertion_point`` are optional — a standalone slot
omits both; a reveal slot carries the revealed image slot id and the
preset's fixed insertion point. ``extra="ignore"`` matches
``FontOutput`` / ``ImageOutput``: a previously-produced ``output.yaml``
carrying since-removed keys still validates.
"""

from __future__ import annotations

import re

from pydantic import ConfigDict, field_validator

from schema.lottie_library import InsertionPoint
from schema.output.node_output import NodeOutput

_ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")


class LottieOutput(NodeOutput):
    """One slot's resolved animation: the chosen preset + recolour map."""

    model_config = ConfigDict(extra="ignore")

    preset_id: str
    preset_file: str
    display_name: str
    # region name -> palette role key (a key in ColorPalette.palette; may
    # be a base role or a derived key like ``primary_third`` / ``card``).
    region_roles: dict[str, str]
    # Reveal slots only: the image slot id this animation reveals, and the
    # preset's fixed insertion point (lifted from preset metadata).
    reveals: str | None = None
    insertion_point: InsertionPoint | None = None

    @field_validator("preset_id", "preset_file", "display_name")
    @classmethod
    def _non_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("LottieOutput field must be non-empty")
        return v

    @field_validator("region_roles")
    @classmethod
    def _region_roles_snake_case(
        cls, v: dict[str, str]
    ) -> dict[str, str]:
        """Both region names (keys) and palette role keys (values) are
        snake_case identifiers."""
        for region, role in v.items():
            if not _ID_PATTERN.match(region):
                raise ValueError(
                    f"recolor region {region!r} must be snake_case"
                )
            if not _ID_PATTERN.match(role):
                raise ValueError(
                    f"palette role {role!r} must be snake_case"
                )
        return v
