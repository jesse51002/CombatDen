-- Orphan recovery: any run still 'running' while WE hold the exclusive worker
-- lock is a dead process (the lease is exclusive + heartbeated). Mark them all
-- failed. NO re-enqueue — the derivation re-selects the gym when it is next due
-- (subject to the run caps); this just clears the stuck 'running' row so the
-- state stays truthful and the run-cap counts stay accurate. RETURNING gym_id
-- only for the recovered-count log.
UPDATE video_run
   SET status = 'failed', error = 'orphaned', finished_at = now()
 WHERE status = 'running'
RETURNING gym_id;
