-- Append one SERVED recommendation to the member's rec history. Written only on
-- the record=true path (CRM previews pass record=false and never write). The
-- table is an append-only event log: each serve INSERTs a new row (no upsert),
-- so a video served N times has N rows. "Times recommended" (COUNT) and "last
-- recommended" (MAX(recommended_at)) are derived by aggregate, not stored.
-- recommended_at defaults to now(). "Already recommended" is global per member.
INSERT INTO member_video_recs (
    member_id, gym_id, video_id, bucket, score
) VALUES (
    CAST(:member_id AS UUID),
    CAST(:gym_id AS UUID),
    :video_id,
    CAST(:bucket AS mood_bucket),
    :score
)
