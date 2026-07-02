-- The class row needed to resolve a check-in / sign-up: the IDENTITY
-- columns (max_capacity / allowed_plan_ids / points_worth / class_name) and
-- the is_active / is_deleted gate flags. gym_classes is identity-only -- the
-- schedule shape lives on gym_class_schedules (checkin_load_schedules.sql).
-- The LEFT JOIN pulls the instance exception's per-occurrence capacity
-- override (exception_max_capacity) for the exact original slot so the
-- caller can resolve the effective room capacity without a second read. A
-- class may occur several times on one day (weekday_slots holds a slot list
-- per day), so the join is keyed on the FULL slot (original_date AND
-- original_time) -- the unique (class_id, original_date, original_time) on
-- class_instance_exceptions keeps it 1:1 per slot.
SELECT
    c.class_id,
    c.gym_id,
    c.class_name,
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
    AND ie.original_time = CAST(:occurrence_time AS TIME)
WHERE c.class_id = CAST(:class_id AS UUID)
  AND c.gym_id = CAST(:gym_id AS UUID)
