-- Enable Row Level Security
ALTER TABLE task_items ENABLE ROW LEVEL SECURITY;

-- Policy: gym staff can read their gym's task items (per-item progress,
-- failures, and the old→new membership linkage the CRM badges from).
CREATE POLICY "Gym staff can view task items"
    ON task_items
    FOR SELECT
    USING (is_gym_admin_or_owner(task_items.gym_id));

-- Task items are backend-executed records: service_role writes only.
REVOKE INSERT, UPDATE, DELETE ON TABLE task_items FROM authenticated;
