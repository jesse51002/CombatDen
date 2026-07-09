-- The enrich sweep's target set (gym-agnostic): DISTINCT videos that still LACK a
-- video_rag row (never enriched) and are under the strike ceiling, drawn from two
-- sources unioned together:
--   (a) feed rows in each gym's LATEST NON-FAILED run (running OR completed — a
--       completed run may still hold pending/accepted stragglers), restricted to
--       scan_status IN ('pending','accepted'): 'pending' is the fresh backlog, and
--       an 'accepted'-without-rag row is an imported preset / pre-RAG carry-forward
--       that MUST get an embedding or it never passes the backend serve gate;
--       'rejected' is terminal, so enriching it is wasted spend (skipped).
--   (b) EVERY owner-section row (video_run_id IS NULL, any gym) — owner videos
--       always carry an embedding for the backend rec / feed reads.
-- Returns the fields the enrich call needs (thumbnail_url feeds the vision part).
WITH latest_run AS (
    SELECT DISTINCT ON (gym_id) run_id
    FROM video_run
    WHERE status <> 'failed'
    ORDER BY gym_id, created_at DESC
),
target_ids AS (
    SELECT f.video_id
    FROM gym_video_feed f
    JOIN latest_run lr ON lr.run_id = f.video_run_id
    WHERE f.scan_status IN ('pending', 'accepted')
    UNION
    SELECT f.video_id
    FROM gym_video_feed f
    WHERE f.video_run_id IS NULL
)
SELECT DISTINCT
    v.video_id,
    v.title,
    v.channel_name,
    v.description,
    v.thumbnail_url,
    v.duration_seconds,
    v.transcript
FROM video v
JOIN target_ids t ON t.video_id = v.video_id
LEFT JOIN video_rag r ON r.video_id = v.video_id
WHERE r.video_id IS NULL
  AND v.failure_count < :max_failures;
