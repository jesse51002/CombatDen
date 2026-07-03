-- Postgres extensions this schema depends on beyond Supabase's defaults.
-- Declarative end-state only — the hand-written migration performs the actual
-- CREATE EXTENSION (per the schema workflow; never auto-generated).
--
-- pgvector: embedding columns (video_rag.embedding,
-- member_video_profile.embedding) + cosine distance (<=>) for the video
-- worker's RAG candidate probes and the member recommendation ranking.
-- Installed into the `extensions` schema (Supabase convention); the `vector`
-- type resolves unqualified via the default search_path.
CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA extensions;
