-- Every class of a gym for the schedule board — soft-DELETED classes
-- INCLUDED (their past occurrences render forever; the reader suppresses a
-- deleted class's in-session/future occurrences). Identity/display columns
-- only; the schedule shape comes from classes_schedules_for_gym.sql and the
-- window overlap is decided by the version expander.
SELECT
    class_id,
    gym_id,
    class_name,
    class_description,
    max_capacity,
    allowed_plan_ids,
    image_url,
    points_worth,
    is_active,
    is_deleted,
    created_at
FROM gym_classes
WHERE gym_id = :gym_id
