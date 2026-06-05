-- Append-only e-signature audit. Phase 1 = reads only (the front-desk clickwrap
-- capture is Phase 2, which adds the INSERT policy below). Members can see their
-- own signatures; gym staff see everything at their gym (mirrors
-- member_reward_redemptions). Rows are never updated or deleted — the legal
-- record is tamper-evident.

-- Enable Row Level Security
ALTER TABLE member_waiver_signatures ENABLE ROW LEVEL SECURITY;

-- Members see their own; staff see everything at their gym
CREATE POLICY "Members and gym staff can view waiver signatures"
    ON member_waiver_signatures
    FOR SELECT
    USING (
        is_gym_admin_or_owner(member_waiver_signatures.gym_id)
        OR EXISTS (
            SELECT 1 FROM members
            WHERE members.member_id = member_waiver_signatures.member_id
            AND members.user_id = auth.uid()
        )
    );

-- Phase 2 (front-desk kiosk capture) will add the INSERT policy, e.g.:
--   CREATE POLICY "Gym staff can record waiver signatures"
--       ON member_waiver_signatures
--       FOR INSERT TO authenticated
--       WITH CHECK (is_gym_admin_or_owner(member_waiver_signatures.gym_id));

-- Append-only legal record: never updated or deleted.
REVOKE UPDATE, DELETE ON TABLE member_waiver_signatures FROM authenticated;
