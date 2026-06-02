ALTER TABLE video_gym_feed ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public can read video gym feed"
    ON video_gym_feed
    FOR SELECT
    TO anon, authenticated
    USING (true);

REVOKE UPDATE (gym_id, video_id) ON TABLE video_gym_feed FROM authenticated;
