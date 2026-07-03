-- Finalise a run as completed (its feed rows now become the gym's latest served
-- run).
UPDATE video_run
   SET status = 'completed', finished_at = now()
 WHERE run_id = CAST(:run_id AS UUID);
