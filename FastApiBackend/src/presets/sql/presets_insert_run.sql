-- Open a new import run for the gym; its feed rows reference this run_id and
-- become the gym's latest (served) run. A preset import is born COMPLETED
-- (status DEFAULT 'completed'), so finished_at is stamped now() to satisfy the
-- video_run_finished_matches_status CHECK ((status='running') = (finished_at IS NULL)).
INSERT INTO video_run (gym_id, finished_at)
VALUES (CAST(:gym_id AS UUID), now()) RETURNING run_id
