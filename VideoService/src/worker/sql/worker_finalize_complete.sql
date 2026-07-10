-- Finalize: complete every 'running' run whose feed is now sufficiently judged.
-- A run completes once the fraction of its feed rows in a TERMINAL scan_status
-- (accepted/rejected) reaches :complete_fraction. terminal = the accepted/rejected
-- count; denominator = ALL the run's feed rows. A run with zero feed rows never
-- groups here (so it can't complete) — the fail query handles those. Runs BEFORE
-- the fail query so a >= :complete_fraction run that is ALSO past the TTL still
-- completes (completion beats the TTL fail).
--
-- The grouped set is RESTRICTED to feed rows of 'running' runs (the INNER JOIN to
-- video_run status='running'): only running runs can be completed, so aggregating
-- the whole gym_video_feed history (every gym, every past run) each tick is pure
-- waste. Cost now scales with the running runs, not total feed history.
UPDATE video_run
   SET status = 'completed', finished_at = now()
 WHERE status = 'running'
   AND run_id IN (
       SELECT f.video_run_id
       FROM gym_video_feed f
       JOIN video_run r
         ON r.run_id = f.video_run_id
        AND r.status = 'running'
       GROUP BY f.video_run_id
       HAVING count(*) FILTER (
                  WHERE f.scan_status IN ('accepted', 'rejected')
              )::float / count(*) >= :complete_fraction
   );
