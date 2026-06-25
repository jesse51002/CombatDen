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
    CURRENT_DATE
)
