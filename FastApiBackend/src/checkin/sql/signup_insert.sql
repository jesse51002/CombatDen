-- Idempotent sign-up create, keyed by the occurrence's full identity
-- (class_id, member_id, original_date, original_time -- a class may occur
-- several times per day, so the time is part of the identity). original_time
-- is stamped from the resolved occurrence at create time. ON CONFLICT DO
-- NOTHING returns no row when the member is already signed up for this
-- occurrence (idempotent re-signup).
INSERT INTO class_signups (gym_id, class_id, member_id, original_date, original_time)
VALUES (
    CAST(:gym_id AS UUID),
    CAST(:class_id AS UUID),
    CAST(:member_id AS UUID),
    CAST(:original_date AS DATE),
    CAST(:original_time AS TIME)
)
ON CONFLICT (class_id, member_id, original_date, original_time) DO NOTHING
RETURNING signup_id
