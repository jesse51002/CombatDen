ALTER TABLE gym_video_query ENABLE ROW LEVEL SECURITY;

-- Gym staff can view their gym's search queries.
CREATE POLICY "Gym employees can view video queries"
    ON gym_video_query
    FOR SELECT
    USING (is_gym_employee(gym_video_query.gym_id));

-- Written by the backend (service_role) via the preset import; clients never write.
REVOKE INSERT, UPDATE, DELETE ON TABLE gym_video_query FROM authenticated;
