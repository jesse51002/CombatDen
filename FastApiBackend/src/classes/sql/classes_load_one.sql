-- A single class row: the expander-relevant columns (used by the reschedule
-- conflict check) plus points_worth (the per-check-in award the un-occur /
-- future-reschedule teardown claws back, loaded once per occurrence). Returns
-- nothing for a deleted/absent class.
SELECT
    class_id,
    gym_id,
    class_time,
    duration_minutes,
    recurring_unit,
    recurring_interval,
    sun, mon, tue, wed, thu, fri, sat,
    sun_instructor_id,
    mon_instructor_id,
    tue_instructor_id,
    wed_instructor_id,
    thu_instructor_id,
    fri_instructor_id,
    sat_instructor_id,
    start_date,
    end_date,
    points_worth
FROM gym_classes
WHERE class_id = :class_id
  AND is_deleted = FALSE
