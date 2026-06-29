-- Insert a gym class (recurrence embedded). recurring_unit and the JSONB
-- allowed_plan_ids are cast functionally (never :p::type — see CLAUDE.md).
-- Returns only class_id; the service re-reads via classes_get.sql so the
-- response carries the joined per-weekday instructor names.
INSERT INTO gym_classes (
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
    points_worth
)
VALUES (
    :gym_id,
    :class_name,
    :class_description,
    :class_time,
    :duration_minutes,
    CAST(:recurring_unit AS recurring_unit),
    :recurring_interval,
    :sun, :mon, :tue, :wed, :thu, :fri, :sat,
    :sun_instructor_id,
    :mon_instructor_id,
    :tue_instructor_id,
    :wed_instructor_id,
    :thu_instructor_id,
    :fri_instructor_id,
    :sat_instructor_id,
    :start_date,
    :end_date,
    :max_capacity,
    CAST(:allowed_plan_ids AS JSONB),
    :image_url,
    :points_worth
)
RETURNING class_id
