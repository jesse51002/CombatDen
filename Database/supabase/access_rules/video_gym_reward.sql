ALTER TABLE video_gym_reward ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public can read video gym rewards"
    ON video_gym_reward
    FOR SELECT
    TO anon, authenticated
    USING (true);

REVOKE UPDATE (reward_id, gym_id) ON TABLE video_gym_reward FROM authenticated;
