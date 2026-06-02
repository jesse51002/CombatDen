"""Python mirrors of the VideoService `video_*` Postgres enums.

Per the Database convention, every Postgres enum is mirrored here with a
`StrEnum` whose member values are character-identical to the DB enum so seeds and
round-trips stay clean. The `video_*` tables are written by VideoService's own
scripts (sync-gyms / import / scrape / scan), which carry their own Pydantic
models; these mirrors exist for convention-completeness and any Database-side use.

Disciplines (gym + video) and source queries are stored as JSONB string arrays,
not Postgres enums, so there is no discipline enum here — the discipline
vocabulary is enforced by VideoService's own `GymType` Pydantic enum on write.
"""

from enum import StrEnum


class VideoGenre(StrEnum):
    """Mirrors the Postgres `video_genre` enum in schemas/video.sql."""

    educational = "educational"
    analysis = "analysis"
    entertainment = "entertainment"
    news = "news"
    interview = "interview"
    vlog = "vlog"
    professional = "professional"
    clips = "clips"
    memes = "memes"


class VideoGymFeedStatus(StrEnum):
    """Mirrors the Postgres `video_gym_feed_status` enum in schemas/video_gym_feed.sql."""

    good = "good"
    rejected = "rejected"


class VideoExecutionType(StrEnum):
    """Mirrors the Postgres `video_execution_type` enum in schemas/video_cost_log.sql."""

    search = "search"
    transcript = "transcript"
    tag = "tag"
    scan = "scan"
