-- Finalize: fail every 'running' run that is pathologically empty or too old.
--   * ZERO feed rows AND older than :zero_row_grace_hours -> 'no feed rows'
--     (a scrape that never wrote pending rows; the grace lets rows that land
--     shortly after the run row not trip this).
--   * else older than :run_ttl_hours -> 'run ttl exceeded' (a run that never
--     reached the completion fraction — the stuck-run backstop).
-- Runs AFTER the complete query, so a run that just completed is no longer
-- 'running' and is skipped here (completion beats the TTL fail).
UPDATE video_run r
   SET status = 'failed',
       finished_at = now(),
       error = CASE
           WHEN NOT EXISTS (
               SELECT 1 FROM gym_video_feed f
               WHERE f.video_run_id = r.run_id
           ) THEN 'no feed rows'
           ELSE 'run ttl exceeded'
       END
 WHERE r.status = 'running'
   AND (
       (
           NOT EXISTS (
               SELECT 1 FROM gym_video_feed f
               WHERE f.video_run_id = r.run_id
           )
           AND r.created_at
               < now() - make_interval(hours => :zero_row_grace_hours)
       )
       OR r.created_at < now() - make_interval(hours => :run_ttl_hours)
   );
