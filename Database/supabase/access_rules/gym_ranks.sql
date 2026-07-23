ALTER TABLE gym_ranks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Gym employees can view ranks"
    ON gym_ranks
    FOR SELECT
    USING (is_gym_employee(gym_ranks.gym_id));

CREATE POLICY "Members can view their gym's ranks"
    ON gym_ranks
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.gym_id = gym_ranks.gym_id
            AND lower(members.email) = lower(auth.jwt() ->> 'email')
        )
    );

CREATE POLICY "Gym staff can insert ranks"
    ON gym_ranks
    FOR INSERT
    TO authenticated
    WITH CHECK (is_gym_admin_or_owner(gym_ranks.gym_id));

CREATE POLICY "Gym staff can update ranks"
    ON gym_ranks
    FOR UPDATE
    USING (is_gym_admin_or_owner(gym_ranks.gym_id))
    WITH CHECK (is_gym_admin_or_owner(gym_ranks.gym_id));

-- main_rank_num_order is reorder-only (moved via the two-phase reorder path);
-- image_url is NOT revoked — it is now a user-writable field (preset default
-- plus manual override in the edit UI).
REVOKE UPDATE (rank_id, gym_id, created_at, main_rank_num_order) ON TABLE gym_ranks FROM authenticated;
