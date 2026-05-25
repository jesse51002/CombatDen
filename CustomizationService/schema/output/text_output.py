"""TextOutput — one resolved text slot in the produced ``output.yaml``.

The LLM picks ``value`` (the rewritten copy) — that is the entire wire
shape per slot. No prose / display name / provenance: the slot's id
plus its description in ``app.yaml`` already explains what the value
is, so storing a second human label adds drift, not signal.

``extra="ignore"`` (not the package-wide ``forbid``) is the same
deliberate exception ``ColorOutput`` / ``ImageOutput`` / ``FontOutput``
make: this group is read back from externally- or previously-produced
``output.yaml`` files and one carrying since-removed keys must still
validate (stale keys dropped, not rejected).
"""

from __future__ import annotations

from pydantic import ConfigDict, field_validator

from schema.output.node_output import NodeOutput


class TextOutput(NodeOutput):
    """One slot's resolved copy: the rewritten string the brand will ship."""

    model_config = ConfigDict(extra="ignore")

    value: str

    @field_validator("value")
    @classmethod
    def _non_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("TextOutput.value must be non-empty")
        return v
