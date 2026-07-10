-- The member's video-taste profile columns, read for BOTH the ownership guard
-- + rebuild decision (gym_id, built_at, whether an embedding exists) AND the
-- rec query's embedding (pgvector text form). Returns no row when the member
-- does not exist. gym_id (frozen on members) is what the caller verifies
-- against the gym it was asked about.
SELECT
    gym_id,
    video_profile_built_at,
    video_profile_embedding_model,
    CAST(video_profile_embedding AS text) AS embedding
FROM members
WHERE member_id = CAST(:member_id AS UUID)
