-- Idempotent sign-up create: ON CONFLICT DO NOTHING on the (class_id,
-- member_id, occurrence_date) unique constraint returns no row when the
-- member is already signed up for this occurrence (idempotent re-signup).
INSERT INTO class_signups (gym_id, class_id, member_id, occurrence_date)
VALUES (
    CAST(:gym_id AS UUID),
    CAST(:class_id AS UUID),
    CAST(:member_id AS UUID),
    CAST(:occurrence_date AS DATE)
)
ON CONFLICT (class_id, member_id, occurrence_date) DO NOTHING
RETURNING signup_id
