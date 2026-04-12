-- Enable Row Level Security
ALTER TABLE gym_history ENABLE ROW LEVEL SECURITY;

-- Policy: Gym staff can read their gym's history (read-only, backend generates data)
CREATE POLICY "Gym staff can view own gym history"
    ON gym_history
    FOR SELECT
    USING (is_gym_admin_or_owner(gym_history.gym_id));
