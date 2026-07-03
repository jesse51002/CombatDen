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


class VideoSource(StrEnum):
    """Mirrors the Postgres `video_source` enum in schemas/video.sql — how a video
    entered the system and whether it can be DELETED: web_query (shared, scraped;
    removal = reject only) vs manual (owner-added, gym-owned; removal = delete)."""

    web_query = "web_query"  # found via the scrape's search queries (bulk path)
    manual = "manual"  # an owner manually pasted a YouTube link


class GymVideoScanStatus(StrEnum):
    """Mirrors the Postgres `gym_video_scan_status` enum in
    schemas/gym_video_feed.sql — a feed row's keep/drop decision."""

    accepted = "accepted"  # served
    rejected = "rejected"  # the rejected list (web_query removals land here)


class GymVideoCurationType(StrEnum):
    """Mirrors the Postgres `gym_video_curation_type` enum in
    schemas/gym_video_feed.sql — how a curation action (accept or reject)
    happened: automatic scan vs. manual owner/admin action."""

    automatic = "automatic"  # the batch scan's keep/drop pass decided this
    manual = "manual"  # an owner/admin acted on it in the UI


class GymVideoSpecSource(StrEnum):
    """Mirrors the Postgres `gym_video_spec_source` enum in
    schemas/gym_video_spec.sql — what produced an (append-only) spec version."""

    feed_update = "feed_update"  # the feed-learning refiner folded in curation
    admin_update = "admin_update"  # the conversational config agent / CRM edit
    system_update = "system_update"  # preset import / automation


class VideoExecutionType(StrEnum):
    """Mirrors the Postgres `video_execution_type` enum in schemas/video_cost_log.sql."""

    search = "search"
    transcript = "transcript"
    tag = "tag"
    enrich = "enrich"
    embed = "embed"
    scan = "scan"


class VideoRunStatus(StrEnum):
    """Mirrors the Postgres `video_run_status` enum in schemas/video_run.sql —
    the lifecycle of a versioned worker run that built a gym's video feed."""

    running = "running"
    completed = "completed"
    failed = "failed"


class VideoWorkerReason(StrEnum):
    """Mirrors the Postgres `video_worker_reason` enum in
    schemas/video_worker_queue.sql — why a gym was queued for a worker run."""

    spec_update = "spec_update"
    manual = "manual"


class MoodBucket(StrEnum):
    """Mirrors the Postgres `mood_bucket` enum in schemas/member_video_profile.sql
    — the five mood clusters (teach / enjoy / inform / human / peak) that member
    video recs are retrieved against. This is the same vocabulary the
    query-generator prompt already uses to enforce feed breadth; a video's bucket
    membership derives deterministically from its `video.tag` genre."""

    teach = "teach"
    enjoy = "enjoy"
    inform = "inform"
    human = "human"
    peak = "peak"
