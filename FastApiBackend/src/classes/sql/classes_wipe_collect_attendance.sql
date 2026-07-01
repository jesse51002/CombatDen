-- The mint engine's wipe collection: a class's attendance (early check-ins)
-- on/after the mint's gym-local floor date. The instant test happens in
-- Python (see classes_wipe_collect_signups.sql). Non-surviving rows are
-- reversed per member via the shared CheckinReverser (points clawback).
SELECT
    member_id,
    original_date,
    original_time
FROM member_attendance
WHERE class_id = CAST(:class_id AS UUID)
  AND original_date >= CAST(:floor_date AS DATE)
