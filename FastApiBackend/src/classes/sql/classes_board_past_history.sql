-- Past materialized occurrences for the schedule board: every class_history row
-- for the gym in the window that has ALREADY ENDED (occurred_at + duration is
-- before NOW -- the class is over, not still in session; a class earlier today
-- that has finished counts as past, but one mid-session does not), joined to its
-- class for the display fields and its recorded attendance count.
--
-- The board renders the past from this immutable table, NOT by re-expanding the
-- current class definition, so editing a class's recurring rules (or deleting
-- the class) never changes or hides occurrences that already happened. The class
-- join is intentionally NOT filtered by is_deleted -- a deleted class's past
-- occurrences still happened and must still render.
SELECT
    ch.class_id,
    ch.gym_id,
    ch.instructor_id,
    ch.occurred_at,
    ch.duration_minutes,
    gc.class_name,
    gc.image_url,
    gc.points_worth,
    gc.max_capacity,
    COUNT(ma.log_id) AS attendance_count
FROM class_history ch
JOIN gym_classes gc ON gc.class_id = ch.class_id
LEFT JOIN member_attendance ma ON ma.class_history_id = ch.class_history_id
WHERE ch.gym_id = CAST(:gym_id AS UUID)
  AND ch.occurred_at >= CAST(:lower AS TIMESTAMPTZ)
  AND ch.occurred_at + ch.duration_minutes * INTERVAL '1 minute'
        <= CAST(:now AS TIMESTAMPTZ)
  AND ch.occurred_at <  CAST(:upper AS TIMESTAMPTZ)
GROUP BY
    ch.class_id,
    ch.gym_id,
    ch.instructor_id,
    ch.occurred_at,
    ch.duration_minutes,
    gc.class_name,
    gc.image_url,
    gc.points_worth,
    gc.max_capacity
