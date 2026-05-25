"""FontOutput — one resolved font slot in the produced ``output.yaml``.

The LLM picks ``family`` + the prose fields (``display_name``,
``description``). ``category`` is read off the Google Fonts catalog
entry after validation — never asked of the LLM — so it cannot drift
from what Google actually serves for that family.

``extra="ignore"`` (not the package-wide ``forbid``) is the same
deliberate exception ``ColorOutput`` / ``ImageOutput`` make: this group
is read back from externally- or previously-produced ``output.yaml``
files and one carrying since-removed keys must still validate (stale
keys dropped, not rejected).
"""

from __future__ import annotations

from pydantic import ConfigDict, field_validator

from schema.output.node_output import NodeOutput


class FontOutput(NodeOutput):
    """One slot's resolved Google Font: the family plus the human prose."""

    model_config = ConfigDict(extra="ignore")

    family: str
    category: str
    display_name: str
    description: str

    @field_validator("family", "category", "display_name", "description")
    @classmethod
    def _non_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("FontOutput field must be non-empty")
        return v
