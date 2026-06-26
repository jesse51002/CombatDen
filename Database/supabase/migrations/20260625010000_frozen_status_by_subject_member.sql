-- HAND-AUTHORED migration (not `supabase db diff` output).
-- Re-keys member_memberships_status.frozen from the PAYER to the SUBJECT MEMBER.
--
-- Before: freeze window was pulled via JOIN members freeze_owner ON
--         freeze_owner.member_id = mm.paid_by_member_id — a payer's freeze would
--         sweep up every membership they bill, including other people's.
-- After:  freeze window is pulled via JOIN members subject_member ON
--         subject_member.member_id = mm.member_id — a freeze pauses exactly that
--         member's own memberships, regardless of who pays for them. A payer's
--         freeze no longer affects the beneficiaries they bill.
--
-- Output columns are unchanged (mm.*, freeze_start_date, freeze_end_date, status).
-- Mirrors schemas/member_memberships.sql (end state).

CREATE OR REPLACE VIEW member_memberships_status
WITH (security_invoker = true)
AS
SELECT mm.*,
    subject_member.freeze_start_date,
    subject_member.freeze_end_date,
    CASE
        WHEN mm.cancel_date IS NOT NULL AND mm.cancel_date <= (now() AT TIME ZONE g.timezone)::date THEN 'cancelled'
        WHEN mm.end_date IS NOT NULL AND mm.end_date <= (now() AT TIME ZONE g.timezone)::date THEN 'ended'
        WHEN subject_member.freeze_start_date IS NOT NULL
             AND subject_member.freeze_end_date IS NOT NULL
             AND subject_member.freeze_start_date <= (now() AT TIME ZONE g.timezone)::date
             AND (now() AT TIME ZONE g.timezone)::date <= subject_member.freeze_end_date THEN 'frozen'
        ELSE 'active'
    END AS status
FROM member_memberships mm
JOIN gyms g ON g.gym_id = mm.gym_id
JOIN members subject_member
    ON subject_member.member_id = mm.member_id;

-- Safety net: CLI migration diffing can strip security_invoker from CREATE VIEW
ALTER VIEW member_memberships_status SET (security_invoker = true);
