"""Per-pass telemetry result, shared by the reconciler and the on-demand
membership invoice fetch.

Lives in ``shared`` (not ``reconciler``) so the memberships invoice-fetch
service can report progress with the same model WITHOUT a
``memberships -> reconciler`` import edge: the reconciler may depend on
memberships, never the reverse.
"""

from pydantic import BaseModel


class SweepResult(BaseModel):
    """The outcome of one fetch / sweep pass over a set of objects."""

    name: str
    processed: int = 0  # rows / members / objects examined
    changed: int = 0  # acted on (deleted / cancelled / recorded)
    skipped: int = 0  # intentionally left (e.g. not-yet-recordable)
    errors: int = 0  # per-item failures that did not abort the pass
