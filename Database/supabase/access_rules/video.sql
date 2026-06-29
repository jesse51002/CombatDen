ALTER TABLE video ENABLE ROW LEVEL SECURITY;

-- Shared (web-query / scraped) videos are public; a gym's CUSTOM videos
-- (gym_id set) are visible only to that gym's staff and its members. (anon has
-- no auth.uid(), so anon sees only the shared rows.)
CREATE POLICY "Read shared videos or own gym's custom videos"
    ON video
    FOR SELECT
    TO anon, authenticated
    USING (
        gym_id IS NULL
        OR is_gym_employee(gym_id)
        OR EXISTS (
            SELECT 1 FROM members
            WHERE members.gym_id = video.gym_id
            AND members.user_id = auth.uid()
        )
    );

-- video_id (PK) and gym_id (ownership) are never client-updatable.
REVOKE UPDATE (video_id, gym_id) ON TABLE video FROM authenticated;
