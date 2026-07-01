-- Recorded attendance per occurrence for the schedule board, keyed by
-- (class_id, original_date) -- the occurrence's identity key. A plain
-- window-bounded GROUP BY over member_attendance; no join (attendance rows
-- carry the occurrence key directly).
SELECT
    class_id,
    original_date,
    COUNT(*) AS attendance_count
FROM member_attendance
WHERE gym_id = CAST(:gym_id AS UUID)
  AND original_date >= CAST(:start_date AS DATE)
  AND original_date <= CAST(:end_date AS DATE)
GROUP BY class_id, original_date
