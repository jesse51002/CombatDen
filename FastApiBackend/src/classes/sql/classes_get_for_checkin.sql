-- The class row needed to resolve a check-in occurrence: the expander-relevant
-- recurrence + schedule columns plus max_capacity / allowed_plan_ids /
-- points_worth / class_name and the is_active / is_deleted gate flags. The
-- LEFT JOIN pulls the instance exception's per-occurrence capacity override
-- (exception_max_capacity) for occurrence_date so the caller can resolve the
-- effective room capacity without a second read. The unique
-- (class_id, original_date) on class_instance_exceptions keeps the join 1:1.
SELECT
    c.class_id,
    c.gym_id,
    c.class_name,
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
    c.max_capacity,
    c.allowed_plan_ids,
    c.points_worth,
    c.is_active,
    c.is_deleted,
    ie.new_max_capacity AS exception_max_capacity
FROM gym_classes c
LEFT JOIN class_instance_exceptions ie
    ON ie.class_id = c.class_id
    AND ie.original_date = CAST(:occurrence_date AS DATE)
WHERE c.class_id = CAST(:class_id AS UUID)
  AND c.gym_id = CAST(:gym_id AS UUID)
