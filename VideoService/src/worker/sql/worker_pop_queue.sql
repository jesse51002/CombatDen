-- Pop the oldest queued gym for a run: delete exactly one row (the oldest by
-- requested_at) and return its gym_id. FOR UPDATE SKIP LOCKED keeps concurrent
-- pops from colliding even though the worker lock already serialises ticks.
DELETE FROM video_worker_queue
 WHERE gym_id = (
     SELECT gym_id
       FROM video_worker_queue
      ORDER BY requested_at
      LIMIT 1
      FOR UPDATE SKIP LOCKED
 )
RETURNING gym_id;
