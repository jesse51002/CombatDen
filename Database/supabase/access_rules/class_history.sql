ALTER TABLE class_history ENABLE ROW LEVEL SECURITY;

-- Members can see history for their gym; staff see all
CREATE POLICY "Users and gym staff can view class history"
    ON class_history
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.gym_id = class_history.gym_id
            AND members.user_id = auth.uid()
        )
        OR is_gym_admin_or_owner(class_history.gym_id)
    );

-- Append-only AND written by the service-role backend ONLY (the materialize /
-- check-in / reconciler paths). No authenticated write path at all: staff never
-- insert history directly — every write goes through the gated backend, so a
-- raw client INSERT can't bypass the capacity / points / snapshot logic.
REVOKE INSERT, UPDATE, DELETE ON TABLE class_history FROM authenticated;
