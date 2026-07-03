-- A member's per-bucket profile embeddings (pgvector text form), read back for
-- rec retrieval. Each bucket's embedding is passed straight back into the
-- candidate query's cosine comparison as :profile_embedding.
SELECT bucket, CAST(embedding AS text) AS embedding
FROM member_video_profile
WHERE member_id = CAST(:member_id AS UUID)
