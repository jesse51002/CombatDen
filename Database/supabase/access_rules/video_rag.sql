ALTER TABLE video_rag ENABLE ROW LEVEL SECURITY;

-- A summary row is visible exactly where its video is (mirrors the video
-- policy): shared pool rows to everyone, a gym's custom videos only to that
-- gym's staff and members.
CREATE POLICY "Read summaries for visible videos"
    ON video_rag
    FOR SELECT
    TO anon, authenticated
    USING (
        EXISTS (
            SELECT 1 FROM video
            WHERE video.video_id = video_rag.video_id
            AND (
                video.gym_id IS NULL
                OR is_gym_admin_or_owner(video.gym_id)
                OR EXISTS (
                    SELECT 1 FROM members
                    WHERE members.gym_id = video.gym_id
                    AND lower(members.email) = lower(auth.jwt() ->> 'email')
                )
            )
        )
    );

-- Written by the VideoService worker's enrich stage only (service level);
-- clients never write summaries or embeddings.
REVOKE INSERT, UPDATE, DELETE ON TABLE video_rag FROM authenticated;
