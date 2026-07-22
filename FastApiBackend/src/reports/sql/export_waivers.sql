-- Raw waiver catalog (identity + current-version pointer) for the gym.
SELECT
    w.waiver_id,
    w.gym_id,
    w.name,
    w.current_version_id,
    w.is_deleted,
    w.waiver_type,
    w.created_at,
    w.updated_at
FROM gym_waivers w
WHERE w.gym_id = CAST(:gym_id AS UUID)
ORDER BY w.created_at ASC, w.waiver_id ASC
