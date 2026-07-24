-- Class check-ins in the report window (member_attendance.occurred_at is the
-- denormalized effective-start instant, a timestamptz), joined to the member
-- and class names. The occurrence's original slot (date + time) is included so
-- the reader can tell apart same-day occurrences of one class.
SELECT
    a.occurred_at,
    a.member_id,
    m.first_name AS member_first_name,
    m.last_name AS member_last_name,
    a.class_id,
    gc.class_name,
    a.original_date,
    a.original_time
FROM member_attendance a
LEFT JOIN members m
    ON m.member_id = a.member_id
   AND m.gym_id = a.gym_id
LEFT JOIN gym_classes gc
    ON gc.class_id = a.class_id
   AND gc.gym_id = a.gym_id
WHERE a.gym_id = CAST(:gym_id AS UUID)
  AND (
      CAST(:all_time AS BOOLEAN)
      OR (
          a.occurred_at >= CAST(:start_utc AS TIMESTAMPTZ)
          AND a.occurred_at < CAST(:end_utc AS TIMESTAMPTZ)
      )
  )
ORDER BY
    a.occurred_at ASC,
    a.class_id ASC,
    a.member_id ASC,
    a.original_time ASC
