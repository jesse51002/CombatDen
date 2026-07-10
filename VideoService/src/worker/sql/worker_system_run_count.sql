-- Count runs of ANY status started across ALL gyms within the rolling window.
-- The worker skips selecting a gym once this reaches the system run cap — the
-- global Apify/quota budget guard, distinct from the per-gym cap enforced inside
-- worker_select_due_gym.sql.
SELECT count(*) AS runs_in_window
FROM video_run
WHERE created_at >= now() - make_interval(hours => :cap_window_hours);
