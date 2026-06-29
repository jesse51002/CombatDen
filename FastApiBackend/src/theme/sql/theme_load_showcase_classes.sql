-- A real gym's active class cards + their resolved instructor, for the showcase.
-- Each class has a per-day instructor; the showcase resolves a single instructor
-- via COALESCE over the day columns (first set wins), joined gym-scoped to
-- gym_employees. Soft-deleted / inactive classes are excluded.
SELECT
    c.class_name AS name,
    c.image_url,
    c.class_description AS description,
    e.first_name,
    e.last_name,
    e.employee_public_description AS instructor_bio,
    e.employee_pic_url AS instructor_image_url
FROM gym_classes c
LEFT JOIN gym_employees e
    ON e.employee_id = COALESCE(
        c.mon_instructor_id,
        c.tue_instructor_id,
        c.wed_instructor_id,
        c.thu_instructor_id,
        c.fri_instructor_id,
        c.sat_instructor_id,
        c.sun_instructor_id
    )
    AND e.gym_id = c.gym_id
WHERE c.gym_id = CAST(:gym_id AS UUID)
  AND c.is_active = TRUE
  AND c.is_deleted = FALSE
ORDER BY c.class_name
