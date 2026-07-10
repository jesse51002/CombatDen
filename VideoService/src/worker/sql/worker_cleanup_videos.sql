-- Delete every video that has hit the hard-error strike ceiling. The enrich /
-- scan sweeps bump failure_count on a hard error and reset it to 0 on success, so
-- a video reaches the ceiling only after repeated failures — it is unusable, so
-- drop it from the pool. FK cascades remove its feed rows, its video_rag row, and
-- any member recs. Runs FIRST each tick so the finalize step's terminal-fraction
-- denominators reflect the shrunk feed. RETURNING video_id only for the log count.
DELETE FROM video
WHERE failure_count >= :max_failures
RETURNING video_id;
