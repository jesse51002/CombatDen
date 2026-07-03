-- A real gym's active class cards + their resolved instructor, for the showcase.
-- Instructors live per-slot inside the CURRENT schedule version's weekday_slots
-- JSONB (gym_class_schedules_current). The showcase resolves a single display
-- instructor per class: the first non-null instructor_id in fixed day order
-- ('all' first — daily/monthly — then mon..sun), then slot order within the
-- day (slots are stored time-sorted). Joined gym-scoped to gym_employees.
-- LEFT JOINs throughout so an instructor-less class still gets a card.
SELECT
    c.class_name AS name,
    c.image_url,
    c.class_description AS description,
    e.first_name,
    e.last_name,
    e.employee_public_description AS instructor_bio,
    e.employee_pic_url AS instructor_image_url
FROM gym_classes c
LEFT JOIN gym_class_schedules_current s ON s.class_id = c.class_id
LEFT JOIN LATERAL (
    SELECT CAST(slot.value ->> 'instructor_id' AS UUID) AS instructor_id
    FROM unnest(ARRAY['all', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'])
         WITH ORDINALITY AS day(key, day_ord)
    CROSS JOIN LATERAL jsonb_array_elements(s.weekday_slots -> day.key)
         WITH ORDINALITY AS slot(value, slot_ord)
    WHERE (slot.value ->> 'instructor_id') IS NOT NULL
    ORDER BY day.day_ord, slot.slot_ord
    LIMIT 1
) pick ON TRUE
LEFT JOIN gym_employees e
    ON e.employee_id = pick.instructor_id
    AND e.gym_id = c.gym_id
WHERE c.gym_id = CAST(:gym_id AS UUID)
  AND c.is_active = TRUE
  AND c.is_deleted = FALSE
ORDER BY c.class_name
