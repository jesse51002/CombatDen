-- Open a new scan/import run for the gym; its feed rows reference this run_id and
-- become the gym's latest (served) run.
INSERT INTO video_run (gym_id) VALUES (CAST(:gym_id AS UUID)) RETURNING run_id
