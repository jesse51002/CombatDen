-- The mint engine's wipe collection: a class's attendance (early check-ins)
-- on/after the mint's gym-local floor date. The instant tests happen in
-- Python — rows store the wall-clock key, and a date's EFFECTIVE start (the
-- proof an occurrence rescheduled into the past already ran, so its real
-- attendance is never reversed by a schedule edit) is derived from its
-- exception row.
SELECT
    member_id,
    original_date,
    original_time
FROM member_attendance
WHERE class_id = CAST(:class_id AS UUID)
  AND original_date >= CAST(:floor_date AS DATE)
