"""LottieOutput — one resolved lottie slot in the produced ``output.yaml``.

The selection LLM picks a preset; the recolour LLM maps each of that
preset's regions to a palette role. The trusted fields — ``preset_file``,
``display_name``, ``insertion_point``, ``speed`` — are lifted off the
library preset metadata after the pick, never asked of the LLM, so they
cannot drift (the same discipline ``FontOutput.category`` follows).

``path`` is the baked, fully-recoloured animation JSON written into the
run dir (``lotties/<slot>.json``) — the colour is baked in at pipeline
time (like an icon's copied SVG), so the app plays the file as-is and
never recolours. ``region_roles`` is kept for provenance/debug only: it
records what each region resolved to, but nothing downstream reads it now
that the colour is baked.

``reveals`` and ``insertion_point`` are optional — a standalone slot
omits both; a reveal slot carries the revealed image slot id, the
preset's fixed insertion point, and a ``hold_seconds`` dwell. ``speed``
is the playback multiplier the app applies to the duration.
``extra="ignore"`` matches ``FontOutput`` / ``ImageOutput``: a
previously-produced ``output.yaml`` carrying since-removed keys still
validates.
"""

from __future__ import annotations

import re

from pydantic import ConfigDict, field_validator

from schema.lottie_library import InsertionPoint
from schema.output.node_output import NodeOutput
from schema.primitives import AbsolutePath

_ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")


class LottieOutput(NodeOutput):
    """One slot's resolved animation: the baked file + its playback args."""

    model_config = ConfigDict(extra="ignore")

    preset_id: str
    preset_file: str
    display_name: str
    # The baked, recoloured animation json in the run dir
    # (``lotties/<slot>.json``) — what the app actually plays.
    path: AbsolutePath
    # Content fingerprint of the delivered JSON bytes — the API's cache-busting
    # ``?v=`` token. Stamped by the Writer at serialize time; empty on a legacy
    # ``output.yaml`` written before this field (URL stays unversioned).
    version: str = ""
    # Playback multiplier (lifted from the preset; 2.0 => half duration).
    speed: float
    # Provenance only: region name -> palette role key it resolved to. The
    # colour is already baked into ``path``; nothing downstream reads this.
    region_roles: dict[str, str]
    # Reveal slots only: the image slot id this animation reveals, and the
    # preset's fixed insertion point (lifted from preset metadata).
    reveals: str | None = None
    insertion_point: InsertionPoint | None = None
    # Reveal slots only: the dwell (seconds) the revealed image holds before
    # it and the animation end (lifted from ``insertion_point.hold_seconds``).
    hold_seconds: float | None = None

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
