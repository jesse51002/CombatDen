-- A gym's video-worker state in one round-trip (scalar subqueries):
--   last_updated    when the feed was last refreshed = newest COMPLETED run's
--                   finished_at (NULL when no run has completed yet).
--   running         a video_run is currently status='running' for the gym.
--   last_run_status the most-recent run's status by created_at (NULL if none).
-- There is no queue (the worker derives its work), so nothing is 'queued' here.
SELECT
    (
        SELECT max(finished_at)
        FROM video_run
        WHERE gym_id = CAST(:gym_id AS UUID)
          AND status = 'completed'
    ) AS last_updated,
    EXISTS (
        SELECT 1 FROM video_run
        WHERE gym_id = CAST(:gym_id AS UUID)
          AND status = 'running'
    ) AS running,
    (
        SELECT status FROM video_run
        WHERE gym_id = CAST(:gym_id AS UUID)
        ORDER BY created_at DESC
        LIMIT 1
    ) AS last_run_status
