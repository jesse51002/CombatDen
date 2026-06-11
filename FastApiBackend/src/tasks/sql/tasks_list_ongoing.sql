-- The CRM's ongoing-tasks poll: a gym's unfinished tasks, oldest first.
SELECT
    task_id,
    gym_id,
    task_type::text AS task_type,
    status::text AS status,
    created_at,
    started_at,
    finished_at
FROM tasks
WHERE gym_id = :gym_id
  AND status IN ('pending', 'running')
ORDER BY created_at, task_id
