-- The existing sign-up row for a (class, member, occurrence) -- read after
-- signup_insert.sql's ON CONFLICT DO NOTHING returns no row, so the create
-- path can still report the existing signup_id on an idempotent repeat.
SELECT signup_id
FROM class_signups
WHERE class_id = CAST(:class_id AS UUID)
  AND member_id = CAST(:member_id AS UUID)
  AND occurrence_date = CAST(:occurrence_date AS DATE)
