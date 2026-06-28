-- A real customer gym's video feed: shared-pool videos a scan/import placed in
-- the gym's feed, plus the owner's own "Your videos". Each row belongs to a
-- versioned run (`video_run_id`) so the serve path can take only the gym's LATEST
-- run; owner-added rows are run-independent (`video_run_id` NULL) and always
-- serve. `scan_status` is the per-row keep/drop decision (the rejected list lives
-- here now, the prod counterpart of the template `video_gym_feed` good/rejected).
-- Removability is a property of the VIDEO (`video.added_via`), not the feed:
-- web_query videos are rejected (kept, `scan_status='rejected'`), manual videos
-- are hard-deleted.

-- The scan keep/drop decision for one feed row.
CREATE TYPE gym_video_scan_status AS ENUM ('accepted', 'rejected');

-- Whether a rejection came from the automatic scan (the batch job's keep/drop
-- pass) or a manual owner/admin action in the UI.
CREATE TYPE gym_video_rejection_type AS ENUM ('automatic', 'manual');

CREATE TABLE gym_video_feed (
    feed_id UUID NOT NULL DEFAULT gen_random_uuid()
        CONSTRAINT pk_gym_video_feed PRIMARY KEY,
    gym_id UUID NOT NULL
        CONSTRAINT fk_gym_video_feed_gym REFERENCES gyms(gym_id) ON DELETE CASCADE,
    video_id TEXT NOT NULL
        CONSTRAINT fk_gym_video_feed_video REFERENCES video(video_id) ON DELETE CASCADE,
    -- The run that produced this row. NULL = the owner's "Your videos" section
    -- (run-independent, always served). Set = a scan/import run (served only when
    -- it's the gym's latest run).
    video_run_id UUID
        CONSTRAINT fk_gym_video_feed_run REFERENCES video_run(run_id) ON DELETE CASCADE,
    -- Keep/drop: 'accepted' serves, 'rejected' is the rejected list. A web_query
    -- removal flips this to 'rejected' (and fills the reject_* audit below);
    -- "Keep" flips it back. Manual videos are hard-deleted, never rejected.
    scan_status gym_video_scan_status NOT NULL DEFAULT 'accepted',
    -- Reject audit = the row's LAST rejection, RETAINED across re-acceptance: a
    -- row can be 'accepted' yet still carry rejection_type / reject_reason /
    -- rejected_at, so we know it was rejected (auto or manual, why, when) and then
    -- switched back. The row toggles accepted <-> rejected freely; this audit just
    -- records the most recent rejection (a manual reject's reason may be blank).
    -- Replaces the old separate removal-log table.
    rejection_type gym_video_rejection_type,
    reject_reason TEXT,
    rejected_at TIMESTAMPTZ,
    -- When this row was last MANUALLY curated (owner reject / keep / readd),
    -- bumped to now() by every manual feed write. NULL = never manually touched
    -- (e.g. an automatic-scan row). The feed-learning refiner reads rows whose
    -- curated_at is newer than the gym's latest feed_update spec version to find
    -- "curation since the last refine" — the unconsumed signal it folds into an
    -- improved spec. Automatic scan rows leave this NULL.
    curated_at TIMESTAMPTZ,
    -- Only rule: a CURRENTLY-rejected row must say how it was rejected. An
    -- accepted row may still carry the prior rejection's audit (history).
    CONSTRAINT rejection_type_when_rejected
        CHECK (scan_status = 'accepted' OR rejection_type IS NOT NULL)
);

-- A video appears at most once per scan run, and at most once in the owner
-- section — but a seeded video may have both (run row + owner row), so the two
-- uniqueness rules are separate partial indexes.
CREATE UNIQUE INDEX uq_gym_video_feed_run_video
    ON gym_video_feed (video_run_id, video_id)
    WHERE video_run_id IS NOT NULL;
CREATE UNIQUE INDEX uq_gym_video_feed_owner_video
    ON gym_video_feed (gym_id, video_id)
    WHERE video_run_id IS NULL;

-- Serve a gym's feed (the join to `video` supplies relevance ordering + cards).
CREATE INDEX idx_gym_video_feed_gym ON gym_video_feed (gym_id);
