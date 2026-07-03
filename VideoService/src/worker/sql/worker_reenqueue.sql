-- Re-enqueue a gym whose run was orphaned. The anti-starvation upsert keeps the
-- OLDEST requested_at on conflict, so a gym already queued (with an even older
-- request) is not pushed back. :requested_at is the orphaned run's created_at,
-- so the gym returns to roughly the position it held when the dead run started.
INSERT INTO video_worker_queue (gym_id, reason, requested_at)
VALUES (CAST(:gym_id AS UUID), 'manual', :requested_at)
ON CONFLICT (gym_id) DO UPDATE
   SET requested_at = LEAST(
           video_worker_queue.requested_at, EXCLUDED.requested_at
       );
