-- Read one task header, gym-scoped (the router 404s on no row).
SELECT
    task_id,
    gym_id,
    task_type::text AS task_type,
    status::text AS status,
    created_at,
    started_at,
    finished_at
FROM tasks
WHERE task_id = :task_id
  AND gym_id = :gym_id
