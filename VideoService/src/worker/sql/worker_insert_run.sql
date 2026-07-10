-- Open this tick's run for the gym as 'running'. Its feed rows reference the
-- returned run_id and become the gym's latest (served) run only once the run
-- finalises to 'completed' (the serve path filters status = 'completed').
INSERT INTO video_run (gym_id, status)
VALUES (CAST(:gym_id AS UUID), 'running')
RETURNING run_id;
