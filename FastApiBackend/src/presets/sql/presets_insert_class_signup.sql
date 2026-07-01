-- One sign-up (reservation) row for a seeded occurrence, past or future --
-- a sign-up is NOT attendance, so this is written independently of
-- presets_insert_attendance.sql. Idempotent: ON CONFLICT DO NOTHING on the
-- (class_id, member_id, occurrence_date) unique constraint, mirroring the
-- live sign-up create path (src/checkin/sql/signup_insert.sql). Executed
-- once per occurrence with a list of param rows (one per member).
INSERT INTO class_signups (
    gym_id, class_id, member_id, occurrence_date
) VALUES (
    CAST(:gym_id AS UUID),
    CAST(:class_id AS UUID),
    CAST(:member_id AS UUID),
    CAST(:occurrence_date AS DATE)
)
ON CONFLICT (class_id, member_id, occurrence_date) DO NOTHING
