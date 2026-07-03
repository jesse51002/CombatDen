-- Per-member RAG profile, one row per MOOD BUCKET: the profile text a
-- member's video recommendations are retrieved against, plus its embedding.
-- Recs pull top-k per bucket then interleave — the bucket quota is what stops
-- retrieval collapsing to all-educational content.
--
-- The five buckets are the same clusters the query-generator prompt already
-- enforces feed breadth with (teach / enjoy / inform / human / peak). A
-- video's bucket membership is DETERMINISTIC CODE from its `video.tag` genre
-- (educational,analysis→teach; entertainment,clips,memes→enjoy; news→inform;
-- interview,vlog→human; professional→peak) — RAG ranks WITHIN a bucket.
--
-- v1 profile_text is a deterministic template built from member data (rank,
-- attendance count/recency, gym disciplines) — the interface is the point;
-- the text gets smarter later. Built lazily by the backend on first recs
-- request, rebuilt when stale (built_at).
CREATE TYPE mood_bucket AS ENUM ('teach', 'enjoy', 'inform', 'human', 'peak');

CREATE TABLE member_video_profile (
    member_id UUID NOT NULL
        CONSTRAINT fk_member_video_profile_member
            REFERENCES members(member_id) ON DELETE CASCADE,
    gym_id UUID NOT NULL
        CONSTRAINT fk_member_video_profile_gym
            REFERENCES gyms(gym_id) ON DELETE CASCADE,
    bucket mood_bucket NOT NULL,
    profile_text TEXT NOT NULL,
    -- Embedding of profile_text. Same model + dimension contract as
    -- video_rag.embedding (they are compared by cosine) — see video_rag.sql.
    embedding vector(1536) NOT NULL,
    embedding_model TEXT NOT NULL,
    built_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT pk_member_video_profile PRIMARY KEY (member_id, bucket),
    CONSTRAINT fk_member_video_profile_member_gym
        FOREIGN KEY (member_id, gym_id)
        REFERENCES members (member_id, gym_id)
);
