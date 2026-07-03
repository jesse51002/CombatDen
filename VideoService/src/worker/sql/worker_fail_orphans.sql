-- Orphan recovery: any run still 'running' while WE hold the exclusive worker
-- lock is a dead process (the lease is exclusive + heartbeated). Mark them all
-- failed and return their gym + original request time so the caller re-enqueues
-- each (preserving its place in line via the request timestamp).
UPDATE video_run
   SET status = 'failed', error = 'orphaned', finished_at = now()
 WHERE status = 'running'
RETURNING gym_id, created_at;
