-- Waiver versions are immutable, append-only legal records: gym staff can view
-- their gym's versions and publish (insert) new ones, but a published version is
-- NEVER mutated or deleted (publishing an edit = a new INSERT row). The absence
-- of UPDATE/DELETE policies already blocks those under RLS; the REVOKE is the
-- belt-and-suspenders the append-only convention requires.

-- Enable Row Level Security
ALTER TABLE gym_waiver_versions ENABLE ROW LEVEL SECURITY;

-- Policy: Gym staff can view their waiver versions (audit history)
CREATE POLICY "Gym staff can view waiver versions"
    ON gym_waiver_versions
    FOR SELECT
    USING (is_gym_admin_or_owner(gym_waiver_versions.gym_id));

-- Policy: Gym staff can publish (insert) a new waiver version
CREATE POLICY "Gym staff can insert waiver versions"
    ON gym_waiver_versions
    FOR INSERT
    TO authenticated
    WITH CHECK (is_gym_admin_or_owner(gym_waiver_versions.gym_id));

-- Immutable: published versions are never updated or deleted.
REVOKE UPDATE, DELETE ON TABLE gym_waiver_versions FROM authenticated;
