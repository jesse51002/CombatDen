ALTER TABLE video_run ENABLE ROW LEVEL SECURITY;

-- Gym staff can view their gym's runs.
CREATE POLICY "Gym employees can view video runs"
    ON video_run
    FOR SELECT
    USING (is_gym_employee(video_run.gym_id));

-- Written by the backend (service_role) on scan / preset import; clients never
-- write runs.
REVOKE INSERT, UPDATE, DELETE ON TABLE video_run FROM authenticated;
