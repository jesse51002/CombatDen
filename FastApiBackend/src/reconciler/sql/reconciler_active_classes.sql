-- Every non-deleted class across all gyms, joined to its gym's IANA timezone,
-- for the NON-billing class-history materialize sweep. One row per class: the
-- recurrence columns + per-day instructor slots the expander needs, plus the
-- gym timezone used to convert each local occurrence to UTC.
--
-- is_active is intentionally NOT filtered: a now-inactive class may still have
-- had PAST occurrences inside the window worth materializing, so only is_deleted
-- excludes a class here. Whether a given occurrence falls within the class's own
-- [start_date, end_date] is decided by the expander, not this query.
SELECT
    c.class_id,
    c.gym_id,
    c.class_time,
    c.duration_minutes,
    c.recurring_unit,
    c.recurring_interval,
    c.sun, c.mon, c.tue, c.wed, c.thu, c.fri, c.sat,
    c.sun_instructor_id,
    c.mon_instructor_id,
    c.tue_instructor_id,
    c.wed_instructor_id,
    c.thu_instructor_id,
    c.fri_instructor_id,
    c.sat_instructor_id,
    c.start_date,
    c.end_date,
    g.timezone
FROM gym_classes c
JOIN gyms g ON g.gym_id = c.gym_id
WHERE c.is_deleted = FALSE
