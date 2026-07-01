-- Insert a gym class IDENTITY row (the schedule shape goes to
-- gym_class_schedules via classes_schedule_insert.sql, in the same
-- transaction). The JSONB allowed_plan_ids is cast functionally (never
-- :p::type — see CLAUDE.md). Returns only class_id; the service re-reads via
-- classes_get.sql so the response carries the joined instructor names.
INSERT INTO gym_classes (
    gym_id,
    class_name,
    class_description,
    max_capacity,
    allowed_plan_ids,
    image_url,
    points_worth
)
VALUES (
    :gym_id,
    :class_name,
    :class_description,
    :max_capacity,
    CAST(:allowed_plan_ids AS JSONB),
    :image_url,
    :points_worth
)
RETURNING class_id
