-- Sign-up counts per occurrence for the schedule board, keyed by (class_id,
-- occurrence_date) -- the gym-local calendar date, unlike
-- classes_attendance_counts.sql which keys off the UTC occurred_at instant.
-- A plain cross-domain read of class_signups (no checkin-domain import): the
-- board shows signup_count for BOTH future and past occurrences, so this is
-- not bounded by "now" the way attendance counts are.
SELECT
    class_id,
    occurrence_date,
    COUNT(*) AS signup_count
FROM class_signups
WHERE gym_id = CAST(:gym_id AS UUID)
  AND occurrence_date >= CAST(:start_date AS DATE)
  AND occurrence_date <= CAST(:end_date AS DATE)
GROUP BY class_id, occurrence_date
