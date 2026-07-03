-- Record one SERVED recommendation into the member's rec history. Written only
-- on the record=true path (CRM previews pass record=false and never write). A
-- re-serve of the same video bumps last_recommended_at / times_recommended
-- instead of inserting, and refreshes the score + bucket it was last served
-- under. "Already recommended" is global per member (unique on member+video).
INSERT INTO member_video_recs (
    member_id, gym_id, video_id, bucket, score
) VALUES (
    CAST(:member_id AS UUID),
    CAST(:gym_id AS UUID),
    :video_id,
    CAST(:bucket AS mood_bucket),
    :score
)
ON CONFLICT (member_id, video_id) DO UPDATE SET
    last_recommended_at = now(),
    times_recommended = member_video_recs.times_recommended + 1,
    score = EXCLUDED.score,
    bucket = EXCLUDED.bucket
