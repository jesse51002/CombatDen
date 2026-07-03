-- A gym's video-worker state in one round-trip (scalar subqueries):
--   last_updated    when the feed was last refreshed = newest COMPLETED run's
--                   finished_at (NULL when no run has completed yet).
--   queued          a pending queue row exists for the gym.
--   running         a video_run is currently status='running' for the gym.
--   last_run_status the most-recent run's status by created_at (NULL if none).
SELECT
    (
        SELECT max(finished_at)
        FROM video_run
        WHERE gym_id = CAST(:gym_id AS UUID)
          AND status = 'completed'
    ) AS last_updated,
    EXISTS (
        SELECT 1 FROM video_worker_queue
        WHERE gym_id = CAST(:gym_id AS UUID)
    ) AS queued,
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
