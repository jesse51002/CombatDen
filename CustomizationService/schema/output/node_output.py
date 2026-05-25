"""NodeOutput — the base every per-item output model inherits.

A node steered by a free-text ``overwrite_specs`` records that instruction
on the slot it produced, so a later reader (the end-user agent) can see
*what made this slot* and re-steer it. The field lives on a shared base so
all six per-item outputs carry it uniformly — ``ColorOutput``, ``FontOutput``,
``TextOutput``, ``IconOutput``, ``ImageOutput``, ``LottieOutput``.

Per-slot, not per-node: the atomic nodes (colour/font/text/icon) resolve
every slot in one call, but the override is recorded against the single
slot it changed, so regenerating one slot never implies the others were
touched.

The base contributes only the field; each subclass keeps its own
``model_config`` (e.g. ``ColorOutput`` stays ``extra="forbid"``) and
validators. ``overwrite_specs`` is an ``OverwriteSpecs`` and defaults to an
empty one, so a slot generated plainly — and an ``output.yaml`` written before
this field — still validates. A bare string (an old fixture, an ergonomic
caller) is coerced to ``OverwriteSpecs(specs=...)`` at the boundary.
"""

from __future__ import annotations

from pydantic import BaseModel, Field, field_validator

from schema.output.overwrite_specs import OverwriteSpecs


class NodeOutput(BaseModel):
    """Base for a node's per-item output: carries the ``OverwriteSpecs`` that
    produced this slot (empty when the slot was generated plainly)."""

    overwrite_specs: OverwriteSpecs = Field(default_factory=OverwriteSpecs)

    @field_validator("overwrite_specs", mode="before")
    @classmethod
    def _coerce_overwrite_specs(cls, v: object) -> object:
        """Accept a bare string (old artifacts / ergonomic callers) or ``None``
        as ``OverwriteSpecs(specs=...)`` / the default."""
        if v is None:
            return OverwriteSpecs()
        if isinstance(v, str):
            return OverwriteSpecs(specs=v)
        return v
