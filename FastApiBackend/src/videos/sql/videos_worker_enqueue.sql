-- Enqueue a gym for a worker run (scrape/enrich/scan). gym_id is the PK, so a
-- gym is queued at most once. On conflict we keep the OLDEST requested_at
-- (LEAST) — anti-self-starvation: a gym repeatedly editing its spec must not
-- keep pushing itself behind newer requests. An existing row's reason stays.
INSERT INTO video_worker_queue (gym_id, reason)
VALUES (CAST(:gym_id AS UUID), CAST(:reason AS video_worker_reason))
ON CONFLICT (gym_id) DO UPDATE
    SET requested_at = LEAST(
        video_worker_queue.requested_at,
        EXCLUDED.requested_at
    )
