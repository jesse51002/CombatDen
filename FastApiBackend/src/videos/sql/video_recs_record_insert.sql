-- Append the SERVED recommendation to the member's rec history and return its
-- new rec_id (the client needs it to POST the click). The table is an
-- append-only event log: each serve INSERTs a new row (no upsert), so a video
-- served N times has N rows. "Times recommended" (COUNT) and "last recommended"
-- (MAX(recommended_at)) are derived by aggregate, not stored. recommended_at
-- defaults to now(). "Already recommended" is global per member. category is the
-- served video's genre (video.tag), the existing video_genre enum.
INSERT INTO member_video_recs (
    member_id, gym_id, video_id, category
) VALUES (
    CAST(:member_id AS UUID),
    CAST(:gym_id AS UUID),
    :video_id,
    CAST(:category AS video_genre)
)
RETURNING rec_id
