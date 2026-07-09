-- Finalize: complete every 'running' run whose feed is now sufficiently judged.
-- A run completes once the fraction of its feed rows in a TERMINAL scan_status
-- (accepted/rejected) reaches :complete_fraction. terminal = the accepted/rejected
-- count; denominator = ALL the run's feed rows. A run with zero feed rows never
-- groups here (so it can't complete) — the fail query handles those. Runs BEFORE
-- the fail query so a >= :complete_fraction run that is ALSO past the TTL still
-- completes (completion beats the TTL fail).
UPDATE video_run
   SET status = 'completed', finished_at = now()
 WHERE status = 'running'
   AND run_id IN (
       SELECT video_run_id
       FROM gym_video_feed
       WHERE video_run_id IS NOT NULL
       GROUP BY video_run_id
       HAVING count(*) FILTER (
                  WHERE scan_status IN ('accepted', 'rejected')
              )::float / count(*) >= :complete_fraction
   );
