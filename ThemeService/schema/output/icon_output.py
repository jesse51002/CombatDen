"""IconOutput — one resolved icon slot in the produced ``output.yaml``.

Every icon slot resolves to a single monochrome SVG written into the
run's ``icons/`` dir, regardless of whether it was MATCHED from a curated
icon set or GENERATED via Recraft when no set icon honestly fit. The
shape is uniform so the MobileApp consumes both the same way:

- ``path``: absolute path of the SVG written for this slot.
- ``icon_set``: the chosen set's id — for matched AND generated icons
  alike (a generated icon is drawn to fit that set's style, so it still
  belongs to the set).
- ``icon_name``: the icon's own name within the set. For a matched icon
  it's the set icon's short-name; for a generated one it's a short
  AI-authored icon name (snake_case-ish).
- ``icon_key``: the user's slot id (the concept they asked for).
- ``prompt``: the Recraft prompt used to generate the SVG — set only for
  GENERATED icons; ``None`` for matched ones (a set icon was copied, no
  prompt), which is also how a consumer tells the two apart. Optional
  like ``ImageOutput.complexity``: older/matched entries omit it.

``extra="ignore"`` (not the package-wide ``forbid``) is the same
deliberate exception ``FontOutput`` / ``ImageOutput`` make: this group is
read back from previously-produced ``output.yaml`` files and one carrying
since-removed keys must still validate (stale keys dropped, not rejected).
"""

from __future__ import annotations

from pydantic import ConfigDict, field_validator

from schema.output.node_output import NodeOutput
from schema.primitives import AbsolutePath


class IconOutput(NodeOutput):
    """One slot's resolved icon: the SVG path plus its source provenance."""

    model_config = ConfigDict(extra="ignore")

    path: AbsolutePath
    # Content fingerprint of the delivered SVG bytes — the API's cache-busting
    # ``?v=`` token. Stamped by the Writer at serialize time; empty on a legacy
    # ``output.yaml`` written before this field (URL stays unversioned).
    version: str = ""
    icon_set: str
    icon_name: str
    icon_key: str
    prompt: str | None = None

    @field_validator("icon_set", "icon_name", "icon_key")
    @classmethod
    def _non_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("IconOutput field must be non-empty")
        return v
