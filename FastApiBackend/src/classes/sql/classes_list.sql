-- All non-deleted classes for a gym, flattened with each class's CURRENT
-- schedule version (gym_class_schedules_current). weekday_slots comes back
-- as raw JSONB; the service resolves instructor names in ONE gym-employees
-- lookup across all rows. include_inactive (structural TRUE/FALSE) controls
-- whether is_active=FALSE classes are included; soft-deleted classes are
-- always excluded (their past still renders on the board, which loads
-- versions directly).
SELECT
    c.class_id,
    c.gym_id,
    c.class_name,
    c.class_description,
    s.duration_minutes,
    s.recurring_unit,
    s.recurring_interval,
    s.weekday_slots,
    s.start_date,
    s.end_date,
    c.max_capacity,
    c.allowed_plan_ids,
    c.image_url,
    c.points_worth,
    c.is_active,
    c.is_deleted,
    c.created_at
FROM gym_classes c
JOIN gym_class_schedules_current s ON s.class_id = c.class_id
WHERE c.gym_id = :gym_id
  AND c.is_deleted = FALSE
  AND ({include_inactive} OR c.is_active = TRUE)
ORDER BY c.class_name ASC
