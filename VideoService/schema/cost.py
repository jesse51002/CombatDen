"""Local mirror of ``Database/python_data/schema/cost.py`` — the generic
``cost_log`` Postgres enums.

VideoService cannot import the Database package's ``schema`` here the way
FastApiBackend does (via `src/shared/db_schema_path.py`): both
``Database/python_data`` and VideoService itself declare a top-level
``schema`` package, so putting both on ``sys.path`` at once collides —
whichever comes first silently shadows the other's submodules (VideoService's
own `schema.gym` / `schema.video_type` / etc. would vanish, or the Database
package's `schema.cost` would). VideoService's standalone read-API Dockerfile
also never has the sibling `Database/` directory in its build context at all.
So this file is kept **character-identical** to the shared source by hand —
sync any change to both.
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
