-- One class IDENTITY row: the gym check (gym_id), points_worth (the
-- per-check-in award the un-occur / future-reschedule teardown claws back,
-- loaded once per occurrence), and the display/status fields. The schedule
-- shape lives on gym_class_schedules (classes_schedules_for_class.sql).
-- Returns nothing for a deleted/absent class.
SELECT
    class_id,
    gym_id,
    class_name,
    max_capacity,
    points_worth,
    is_active,
    is_deleted
FROM gym_classes
WHERE class_id = :class_id
  AND is_deleted = FALSE
