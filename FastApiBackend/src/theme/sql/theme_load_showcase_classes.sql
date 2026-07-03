-- A real gym's active class cards + their resolved instructor, for the showcase.
-- Instructors live per-slot inside the class's CURRENT schedule version's
-- weekday_slots JSONB (gym_class_schedules_current view). The showcase resolves
-- a single instructor: the first non-null instructor_id scanning days in
-- mon..sun order ("all" — the daily/monthly key — last) and each day's slots in
-- their stored (time-ascending) order, joined gym-scoped to gym_employees.
-- Soft-deleted / inactive classes are excluded.
SELECT
    c.class_name AS name,
    c.image_url,
    c.class_description AS description,
    e.first_name,
    e.last_name,
    e.employee_public_description AS instructor_bio,
    e.employee_pic_url AS instructor_image_url
FROM gym_classes c
LEFT JOIN gym_class_schedules_current s
    ON s.class_id = c.class_id
LEFT JOIN LATERAL (
    SELECT CAST(slot.value ->> 'instructor_id' AS UUID) AS instructor_id
    FROM jsonb_each(s.weekday_slots) AS day(key, value)
    CROSS JOIN LATERAL jsonb_array_elements(day.value)
        WITH ORDINALITY AS slot(value, ord)
    WHERE slot.value ->> 'instructor_id' IS NOT NULL
    ORDER BY
        array_position(
            ARRAY['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun', 'all'],
            day.key
        ),
        slot.ord
    LIMIT 1
) resolved ON TRUE
LEFT JOIN gym_employees e
    ON e.employee_id = resolved.instructor_id
    AND e.gym_id = c.gym_id
WHERE c.gym_id = CAST(:gym_id AS UUID)
  AND c.is_active = TRUE
  AND c.is_deleted = FALSE
ORDER BY c.class_name
