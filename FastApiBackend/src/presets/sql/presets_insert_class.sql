INSERT INTO gym_classes (
    gym_id, class_name, class_description, image_url,
    points_worth, is_active, is_deleted,
    class_time, duration_minutes, recurring_unit, recurring_interval,
    mon, tue, wed, thu, fri, sat, sun,
    mon_instructor_id, tue_instructor_id, wed_instructor_id,
    thu_instructor_id, fri_instructor_id,
    start_date
) VALUES (
    CAST(:gym_id AS UUID), :class_name, :class_description, :image_url,
    :points_worth, TRUE, FALSE,
    CAST(:class_time AS TIME), :duration_minutes, 'weekly', 1,
    TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, FALSE,
    CAST(:instructor_id AS UUID), CAST(:instructor_id AS UUID), CAST(:instructor_id AS UUID),
    CAST(:instructor_id AS UUID), CAST(:instructor_id AS UUID),
    -- Backdated ~35 days so the weekly recurrence already covers the past month
    -- (the seeded class_history + attendance window) AND the current week. The
    -- schedule board expands from start_date forward, so this only means the
    -- class "has been running" for a month — the live board is unaffected.
    CAST(CURRENT_DATE - INTERVAL '35 days' AS DATE)
)
RETURNING class_id, start_date
