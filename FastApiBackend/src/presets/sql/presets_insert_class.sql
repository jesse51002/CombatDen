-- Insert a gym class IDENTITY row only (gym_classes). The schedule shape
-- (time, duration, recurrence, weekday slots, instructor) goes to
-- gym_class_schedules via presets_insert_class_schedule.sql, in the same
-- transaction. The JSONB allowed_plan_ids column isn't set by the import
-- today (NULL = all plans), so it's omitted here rather than bound to a
-- hardcoded NULL.
INSERT INTO gym_classes (
    gym_id, class_name, class_description, image_url,
    points_worth, is_active, is_deleted
) VALUES (
    CAST(:gym_id AS UUID), :class_name, :class_description, :image_url,
    :points_worth, TRUE, FALSE
)
-- max_capacity isn't set above (no capacity column in the INSERT list), so
-- this always returns NULL today -- but the sign-up seeding reads it here
-- rather than assuming NULL, so it stays correct if a capacity ever gets set.
RETURNING class_id, max_capacity
