-- gym_waivers is plain gym config (no Stripe): gym staff author waivers
-- directly. Gated like gym_classes / gym_rewards — gym-staff SELECT plus
-- gym-scoped INSERT / UPDATE / DELETE, identity columns immutable.

-- Enable Row Level Security
ALTER TABLE gym_waivers ENABLE ROW LEVEL SECURITY;

-- Policy: Gym staff can view their waivers
CREATE POLICY "Gym staff can view waivers"
    ON gym_waivers
    FOR SELECT
    USING (is_gym_admin_or_owner(gym_waivers.gym_id));

-- Policy: Gym staff can author (insert) waivers for their gym
CREATE POLICY "Gym staff can insert waivers"
    ON gym_waivers
    FOR INSERT
    TO authenticated
    WITH CHECK (is_gym_admin_or_owner(gym_waivers.gym_id));

-- Policy: Gym staff can rename / re-point current version / archive their waivers
CREATE POLICY "Gym staff can update waivers"
    ON gym_waivers
    FOR UPDATE
    USING (is_gym_admin_or_owner(gym_waivers.gym_id))
    WITH CHECK (is_gym_admin_or_owner(gym_waivers.gym_id));

-- Policy: Gym staff can delete their waivers (the normal path archives via
-- is_deleted, but staff own this config outright)
CREATE POLICY "Gym staff can delete waivers"
    ON gym_waivers
    FOR DELETE
    USING (is_gym_admin_or_owner(gym_waivers.gym_id));

-- Identity columns stay immutable.
REVOKE UPDATE (waiver_id, gym_id, created_at) ON TABLE gym_waivers FROM authenticated;
