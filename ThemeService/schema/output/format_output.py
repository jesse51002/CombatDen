"""FormatOutput — one resolved format slot in the produced ``output.yaml``.

The LLM picks ``value``: one token from that slot's own declared
vocabulary in ``app.yaml``. That token is the entire contract with the
consuming client — it is written verbatim, never normalised, because the
client parses it literally against its own enum.

``reason`` is the one-line justification the same call produced. Unlike
the classification node — whose wire shape is a bare string, so its
carrier's ``reason`` is call-local and dropped — a format slot is a real
output-group item, and the group already carries prose elsewhere
(``FontOutput.description``). Keeping it is what makes a run's
arrangement decisions reviewable by a human after the fact without
re-running (and re-paying for) anything.

``extra="ignore"`` (not the package-wide ``forbid``) is the same
deliberate exception ``TextOutput`` / ``FontOutput`` / ``ImageOutput``
make: this group is read back from previously-produced ``output.yaml``
files and one carrying since-removed keys must still validate (stale keys
dropped, not rejected).
"""

from __future__ import annotations

from pydantic import ConfigDict, field_validator

from schema.output.node_output import NodeOutput


class FormatOutput(NodeOutput):
    """One slot's resolved format: the chosen wire token plus why."""

    model_config = ConfigDict(extra="ignore")

    value: str
    reason: str = ""

    @field_validator("value")
    @classmethod
    def _non_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("FormatOutput.value must be non-empty")
        return v
