"""Python mirrors of the generic `cost_log` Postgres enums.

Per the Database convention, every Postgres enum is mirrored here with a
`StrEnum` whose member values are character-identical to the DB enum so seeds and
round-trips stay clean. `cost_log` is service-role-written by the pipeline
workers, which carry their own models; these mirrors exist for
convention-completeness and any Database-side use.
"""

from enum import StrEnum


class CostSource(StrEnum):
    """Mirrors the Postgres `cost_source` enum in schemas/cost_log.sql — the
    producing system a cost row belongs to (extensible)."""

    video = "video"


class CostStage(StrEnum):
    """Mirrors the Postgres `cost_stage` enum in schemas/cost_log.sql — the
    cost-bearing pipeline stage a spend row is attributed to."""

    search = "search"
    transcript = "transcript"
    tag = "tag"
    enrich = "enrich"
    embed = "embed"
    scan = "scan"
