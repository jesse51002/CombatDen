-- Recompute a task's status from its items. Called after a claim (flips the
-- task to 'running' and stamps its first started_at) and after each item
-- reaches a terminal state ('failed' wins over 'completed'; any unfinished
-- item keeps the task 'running').
UPDATE tasks t
SET status = CAST(derived.status AS task_status),
    started_at = COALESCE(t.started_at, now()),
    finished_at = CASE
        WHEN derived.status IN ('completed', 'failed')
            THEN COALESCE(t.finished_at, now())
        ELSE NULL
    END
FROM (
    SELECT
        CASE
            WHEN COUNT(*) FILTER (WHERE ti.status = 'failed') > 0
                 AND COUNT(*) FILTER (
                     WHERE ti.status IN ('pending', 'running')
                 ) = 0
                THEN 'failed'
            WHEN COUNT(*) FILTER (WHERE ti.status <> 'completed') = 0
                THEN 'completed'
            ELSE 'running'
        END AS status
    FROM task_items ti
    WHERE ti.task_id = :task_id
) AS derived
WHERE t.task_id = :task_id
