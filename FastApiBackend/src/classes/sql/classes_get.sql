-- A single class: the gym_classes identity row flattened with its CURRENT
-- schedule version (gym_class_schedules_current). weekday_slots comes back as
-- raw JSONB; the service resolves each slot's instructor to a display name
-- via ONE gym-employees lookup (classes_instructor_names.sql) and merges in
-- Python — no per-slot joins. The response shape is the flat
-- class-as-it-stands-now the CRM form edits; window/board reads load the
-- full version history instead.
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
WHERE c.class_id = :class_id
