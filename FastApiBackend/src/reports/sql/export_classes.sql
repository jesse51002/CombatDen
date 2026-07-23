-- Raw class identities for the gym. allowed_plan_ids is a JSONB array rendered
-- as its text form (NULL = all plans allowed).
SELECT
    gc.class_id,
    gc.gym_id,
    gc.class_name,
    gc.class_description,
    CAST(gc.allowed_plan_ids AS TEXT) AS allowed_plan_ids,
    gc.max_capacity,
    gc.image_url,
    gc.points_worth,
    gc.is_active,
    gc.is_deleted,
    gc.created_at
FROM gym_classes gc
WHERE gc.gym_id = CAST(:gym_id AS UUID)
ORDER BY gc.created_at ASC, gc.class_id ASC
