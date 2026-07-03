-- The video ids the previous completed run already verdicted (its feed rows). In
-- incremental mode (criteria unchanged) these are excluded from this run's
-- candidates — their verdicts are carried forward instead of re-scanned.
SELECT video_id
FROM gym_video_feed
WHERE video_run_id = CAST(:prev_run_id AS UUID);
