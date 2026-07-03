-- Upsert one member video-profile bucket row: its profile text + embedding.
-- One row per (member_id, bucket) — a rebuild overwrites the text/embedding and
-- re-stamps built_at. gym_id is set on insert and never changed (the member's
-- gym is fixed; the composite FK (member_id, gym_id) guarantees consistency).
-- The embedding is bound as its pgvector text form ('[0.1,0.2,...]').
INSERT INTO member_video_profile (
    member_id, gym_id, bucket, profile_text, embedding, embedding_model
) VALUES (
    CAST(:member_id AS UUID),
    CAST(:gym_id AS UUID),
    CAST(:bucket AS mood_bucket),
    :profile_text,
    CAST(:embedding AS vector),
    :embedding_model
)
ON CONFLICT (member_id, bucket) DO UPDATE SET
    profile_text = EXCLUDED.profile_text,
    embedding = EXCLUDED.embedding,
    embedding_model = EXCLUDED.embedding_model,
    built_at = now()
