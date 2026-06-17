-- Enable Row Level Security
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;

-- Policy: gym staff can read their gym's tasks (the CRM polls task progress).
CREATE POLICY "Gym staff can view tasks"
    ON tasks
    FOR SELECT
    USING (is_gym_admin_or_owner(tasks.gym_id));

-- Tasks are backend-executed records: service_role writes only.
REVOKE INSERT, UPDATE, DELETE ON TABLE tasks FROM authenticated;
