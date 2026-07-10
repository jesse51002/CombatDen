-- Write the member's rebuilt video-taste profile: the LLM summary, its
-- embedding (pgvector text form), the embedding model, and the build time.
-- service_role only (these columns are client-immutable).
UPDATE members
SET video_profile_summary = :summary,
    video_profile_embedding = CAST(:embedding AS vector),
    video_profile_embedding_model = :embedding_model,
    video_profile_built_at = now()
WHERE member_id = CAST(:member_id AS UUID)
