-- The class row needed to resolve a check-in / sign-up: the IDENTITY
-- columns (max_capacity / allowed_plan_ids / points_worth / class_name) and
-- the is_active / is_deleted gate flags. gym_classes is identity-only -- the
-- schedule shape lives on gym_class_schedules (checkin_load_schedules.sql).
-- The LEFT JOIN pulls the instance exception's per-occurrence capacity
-- override (exception_max_capacity) for occurrence_date so the caller can
-- resolve the effective room capacity without a second read. The unique
-- (class_id, original_date) on class_instance_exceptions keeps the join 1:1.
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
WHERE c.class_id = CAST(:class_id AS UUID)
  AND c.gym_id = CAST(:gym_id AS UUID)
