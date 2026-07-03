-- The gym's most recent COMPLETED run before this tick (the current 'running'
-- run is excluded by the status filter). Its run_id anchors incremental
-- carry-forward; its created_at anchors the criteria-change comparison. No rows
-- when the gym has never completed a run.
SELECT run_id, created_at
FROM video_run
WHERE gym_id = CAST(:gym_id AS UUID)
  AND status = 'completed'
ORDER BY created_at DESC
LIMIT 1;
