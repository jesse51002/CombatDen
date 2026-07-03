-- Finalise a run as failed with a truncated error summary. NO re-enqueue: a
-- deterministic failure needs a manual CRM re-trigger (poison guard); a crash
-- orphan is recovered separately on the next lock acquisition.
UPDATE video_run
   SET status = 'failed', error = :error, finished_at = now()
 WHERE run_id = CAST(:run_id AS UUID);
