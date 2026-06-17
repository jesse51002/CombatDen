-- Crash-recovery sweep: every unfinished task across all gyms, oldest first.
-- The sweep re-runs each; the per-item claims decide what is actually
-- runnable (pending, or a stale 'running' left by a dead process).
SELECT task_id
FROM tasks
WHERE status IN ('pending', 'running')
ORDER BY created_at, task_id
