-- Sign-up counts per occurrence for the schedule board, keyed by (class_id,
-- original_date, original_time) -- the occurrence's full identity key, same
-- as classes_attendance_counts.sql. A plain cross-domain read of
-- class_signups (no checkin-domain import): the board shows signup_count for
-- BOTH future and past occurrences, so this is not bounded by "now".
SELECT
    class_id,
    original_date,
    original_time,
    COUNT(*) AS signup_count
FROM class_signups
WHERE gym_id = CAST(:gym_id AS UUID)
  AND original_date >= CAST(:start_date AS DATE)
  AND original_date <= CAST(:end_date AS DATE)
GROUP BY class_id, original_date, original_time
