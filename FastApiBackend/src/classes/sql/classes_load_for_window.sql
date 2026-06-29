-- All non-deleted classes of a gym whose recurrence span can overlap the
-- [start_date, end_date] window. Full column set so the reader can both build
-- the expander input and enrich the board rows.
SELECT
    class_id,
    gym_id,
    class_name,
    class_description,
    class_time,
    duration_minutes,
    recurring_unit,
    recurring_interval,
    sun, mon, tue, wed, thu, fri, sat,
    sun_instructor_id,
    mon_instructor_id,
    tue_instructor_id,
    wed_instructor_id,
    thu_instructor_id,
    fri_instructor_id,
    sat_instructor_id,
    start_date,
    end_date,
    max_capacity,
    allowed_plan_ids,
    image_url,
    points_worth,
    is_active,
    is_deleted,
    created_at
FROM gym_classes
WHERE gym_id = :gym_id
  AND is_deleted = FALSE
  AND start_date <= :end_date
  AND (end_date IS NULL OR end_date >= :start_date)
