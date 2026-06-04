-- gym_discounts is no longer a Stripe-gated table: coupons are computed at sync
-- and written back onto the applied-discount snapshots, so the preset carries no
-- stripe_*_id and is valid the moment it is inserted. Discounts are therefore
-- plain gym config authored by staff — gated like gym_classes / gym_rewards:
-- gym-staff SELECT plus gym-scoped INSERT / UPDATE / DELETE, with the identity
-- columns held immutable. The former hide_incomplete_stripe_records restrictive
-- policy and the service_role-write-only posture are gone (no coupon to gate on).

-- Enable Row Level Security
ALTER TABLE gym_discounts_unfiltered ENABLE ROW LEVEL SECURITY;

-- Policy: Gym staff can view their discounts
CREATE POLICY "Gym staff can view discounts"
    ON gym_discounts_unfiltered
    FOR SELECT
    USING (is_gym_admin_or_owner(gym_discounts_unfiltered.gym_id));

-- Policy: Gym staff can author (insert) discount presets for their gym
CREATE POLICY "Gym staff can insert discounts"
    ON gym_discounts_unfiltered
    FOR INSERT
    TO authenticated
    WITH CHECK (is_gym_admin_or_owner(gym_discounts_unfiltered.gym_id));

-- Policy: Gym staff can edit their discount presets (name / value / lifetime)
-- and archive them (is_deleted). Edits affect only future applications;
-- existing applied snapshots are immutable and untouched.
CREATE POLICY "Gym staff can update discounts"
    ON gym_discounts_unfiltered
    FOR UPDATE
    USING (is_gym_admin_or_owner(gym_discounts_unfiltered.gym_id))
    WITH CHECK (is_gym_admin_or_owner(gym_discounts_unfiltered.gym_id));

-- Policy: Gym staff can delete their discount presets (hard delete; the normal
-- path archives via is_deleted, but staff own this config outright).
CREATE POLICY "Gym staff can delete discounts"
    ON gym_discounts_unfiltered
    FOR DELETE
    USING (is_gym_admin_or_owner(gym_discounts_unfiltered.gym_id));

-- Identity columns stay immutable.
REVOKE UPDATE (discount_id, gym_id, created_at) ON TABLE gym_discounts_unfiltered FROM authenticated;

-- View-level permissions: reads go through the passthrough view; writes go to
-- the base table.
REVOKE INSERT, UPDATE, DELETE ON gym_discounts FROM authenticated;
