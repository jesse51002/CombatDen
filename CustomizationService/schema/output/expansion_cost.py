"""ExpansionCostLog — the append-only spend log for `expand` passes.

A run's ``output.yaml`` keeps the cost of the original full pipeline run
untouched. Every later ``expand`` pass (seed the done nodes from a saved
``output.yaml``, generate only what's missing) spends money on just the
nodes it regenerated; that spend lands here, in a sibling
``expansion_cost.yaml``, as one appended ``ExpansionEntry`` per pass —
never folded into ``output.yaml``'s ``cost``.

A list (not a single figure) so the file is a full ledger: how many
expand passes a run has had, when, which nodes each generated, and what
each cost. ``extra="ignore"`` matches the other output-read models
(``Output`` / ``RunCost`` / the ``*Set`` groups): a ledger written before
a future field is added must still validate, the stale/unknown keys
dropped rather than rejected.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field, field_validator

from schema.output.expansion_kind import ExpansionKind
from schema.output.overwrite_specs import OverwriteSpecs
from schema.output.run_cost import RunCost


class ExpansionEntry(BaseModel):
    """One pass over an existing run (an expand or a regenerate).

    ``kind`` says which operation this was (the ledger is the unified log).
    ``expanded_at`` is the UTC stamp of the pass (same ``%Y%m%dT%H%M%SZ``
    shape as a run id, so entries sort chronologically). ``generated`` is
    the executor node keys this pass actually ran — the ``color`` / ``font``
    / ``text`` / ``icon`` roots and per-slot image/lottie ids that weren't
    yet done (expand) or were re-made (regenerate). ``overwrite_specs`` is the
    ``OverwriteSpecs`` applied this pass (its ``specs`` / ``image_to_image``) —
    empty for a plain expand — so the log says exactly what was asked of the
    re-made slots. ``cost`` is that pass's spend alone
    (the fresh paid services accumulate only this pass's calls), in the same
    ``RunCost`` shape the full run uses.
    """

    model_config = ConfigDict(extra="ignore")

    kind: ExpansionKind = ExpansionKind.UNKNOWN
    expanded_at: str
    generated: list[str] = Field(default_factory=list)
    overwrite_specs: OverwriteSpecs = Field(default_factory=OverwriteSpecs)
    cost: RunCost

    @field_validator("kind", mode="before")
    @classmethod
    def _coerce_kind(cls, v: object) -> ExpansionKind:
        """Resilient parse: an old row without ``kind`` (``None``) or one
        carrying a since-removed value loads as ``UNKNOWN``, never raises."""
        return ExpansionKind.coerce(v)


class ExpansionCostLog(BaseModel):
    """The ordered ledger of every ``expand`` pass for one run.

    Read back, appended to, and re-written on each pass. An absent
    ``expansion_cost.yaml`` is simply an empty log (a run that has never
    been expanded).
    """

    model_config = ConfigDict(extra="ignore")

    expansions: list[ExpansionEntry] = Field(default_factory=list)
