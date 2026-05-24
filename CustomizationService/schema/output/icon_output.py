"""IconOutput — one resolved icon slot in the produced ``output.yaml``.

Every icon slot resolves to a single monochrome SVG written into the
run's ``icons/`` dir, regardless of whether it was MATCHED from a curated
icon set or GENERATED via Recraft when no set icon honestly fit. The
shape is uniform so the MobileApp consumes both the same way:

- ``path``: absolute path of the SVG written for this slot.
- ``icon_set``: the chosen set's id for a matched icon; the sentinel
  ``"generated"`` for a generated one.
- ``icon_set_name``: the set's human display name for a matched icon;
  ``"Generated"`` for a generated one.
- ``icon_key``: the user's slot id (the concept they asked for).
- ``prompt``: the Recraft prompt used to generate the SVG — set only for
  GENERATED icons; ``None`` for matched ones (a set icon was copied, no
  prompt). Optional like ``ImageOutput.complexity``: older/matched
  entries omit it.

``extra="ignore"`` (not the package-wide ``forbid``) is the same
deliberate exception ``FontOutput`` / ``ImageOutput`` make: this group is
read back from previously-produced ``output.yaml`` files and one carrying
since-removed keys must still validate (stale keys dropped, not rejected).
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, field_validator

from schema.primitives import AbsolutePath


class IconOutput(BaseModel):
    """One slot's resolved icon: the SVG path plus its source provenance."""

    model_config = ConfigDict(extra="ignore")

    path: AbsolutePath
    icon_set: str
    icon_set_name: str
    icon_key: str
    prompt: str | None = None

    @field_validator("icon_set", "icon_set_name", "icon_key")
    @classmethod
    def _non_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("IconOutput field must be non-empty")
        return v
