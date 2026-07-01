-- All non-deleted classes for a gym, flattened with each class's CURRENT
-- schedule version (gym_class_schedules_current), instructor slots resolved to
-- names. include_inactive (structural TRUE/FALSE) controls whether
-- is_active=FALSE classes are included; soft-deleted classes are always
-- excluded (their past still renders on the board, which loads versions
-- directly).
SELECT
    c.class_id,
    c.gym_id,
    c.class_name,
    c.class_description,
    s.class_time,
    s.duration_minutes,
    s.recurring_unit,
    s.recurring_interval,
    s.sun, s.mon, s.tue, s.wed, s.thu, s.fri, s.sat,
    s.sun_instructor_id,
    s.mon_instructor_id,
    s.tue_instructor_id,
    s.wed_instructor_id,
    s.thu_instructor_id,
    s.fri_instructor_id,
    s.sat_instructor_id,
    (e_sun.first_name || ' ' || e_sun.last_name) AS sun_instructor_name,
    (e_mon.first_name || ' ' || e_mon.last_name) AS mon_instructor_name,
    (e_tue.first_name || ' ' || e_tue.last_name) AS tue_instructor_name,
    (e_wed.first_name || ' ' || e_wed.last_name) AS wed_instructor_name,
    (e_thu.first_name || ' ' || e_thu.last_name) AS thu_instructor_name,
    (e_fri.first_name || ' ' || e_fri.last_name) AS fri_instructor_name,
    (e_sat.first_name || ' ' || e_sat.last_name) AS sat_instructor_name,
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
LEFT JOIN gym_employees e_sun ON e_sun.employee_id = s.sun_instructor_id
LEFT JOIN gym_employees e_mon ON e_mon.employee_id = s.mon_instructor_id
LEFT JOIN gym_employees e_tue ON e_tue.employee_id = s.tue_instructor_id
LEFT JOIN gym_employees e_wed ON e_wed.employee_id = s.wed_instructor_id
LEFT JOIN gym_employees e_thu ON e_thu.employee_id = s.thu_instructor_id
LEFT JOIN gym_employees e_fri ON e_fri.employee_id = s.fri_instructor_id
LEFT JOIN gym_employees e_sat ON e_sat.employee_id = s.sat_instructor_id
WHERE c.gym_id = :gym_id
  AND c.is_deleted = FALSE
  AND ({include_inactive} OR c.is_active = TRUE)
ORDER BY s.class_time ASC, c.class_name ASC
