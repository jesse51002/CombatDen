-- The authorization layer (who may pay for whom). Backend-managed: rows are
-- created via the link endpoint after a waiver is signed, and deleted via
-- unlink — both at service_role (mirrors how the former
-- members.account_linked_to_id was service_role-managed). Clients never write
-- directly. Gym staff and the two involved members can read.

-- Enable Row Level Security
ALTER TABLE member_authorized_payers ENABLE ROW LEVEL SECURITY;

-- Gym staff see everything at their gym; involved members see their own links.
CREATE POLICY "Gym staff and involved members can view authorized payers"
    ON member_authorized_payers
    FOR SELECT
    USING (
        is_gym_admin_or_owner(member_authorized_payers.gym_id)
        OR EXISTS (
            SELECT 1 FROM members
            WHERE members.user_id = auth.uid()
            AND members.member_id IN (
                member_authorized_payers.member_id,
                member_authorized_payers.payer_member_id
            )
        )
    );

-- Backend-managed via service_role — clients never insert/update/delete.
REVOKE INSERT, UPDATE, DELETE
    ON TABLE member_authorized_payers FROM authenticated;
