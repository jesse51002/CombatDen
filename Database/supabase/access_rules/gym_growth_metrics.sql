-- Enable Row Level Security
ALTER TABLE gym_growth_metrics ENABLE ROW LEVEL SECURITY;

-- Service-role-WRITE-only: every row is written by the backend's growth compute
-- job. Clients never write metrics.
REVOKE INSERT, UPDATE, DELETE ON TABLE gym_growth_metrics FROM authenticated;

-- Policy: Gym staff can read their own gym's computed metrics (read-only).
CREATE POLICY "Gym staff can view own gym growth metrics"
    ON gym_growth_metrics
    FOR SELECT
    USING (is_gym_admin_or_owner(gym_growth_metrics.gym_id));
