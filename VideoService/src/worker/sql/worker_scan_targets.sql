-- The scan sweep's target set (gym-agnostic, grouped by gym): the feed rows in
-- each gym's LATEST NON-FAILED run whose video is ALREADY enriched (a video_rag
-- row exists) and is under the strike ceiling, matching EITHER arm:
--   (A) scan_status = 'pending' — a candidate row the worker wrote but has not yet
--       settled (its first-ever verdict), OR
--   (B) curation_type = 'automatic' AND the gym has a 'feed_update' gym_video_spec
--       version that has SETTLED (created_at <= now() - the re-scan delay) and is
--       NEWER than this row's last scan (created_at > COALESCE(scanned_at,
--       '-infinity')) — the feed-learning RE-SCAN: an auto-verdicted row (pending,
--       accepted, or rejected) is re-judged in place against the new criteria.
-- Arm B NEVER includes a curation_type='manual' row, so an owner's explicit
-- keep/reject verdict is never re-scanned. Both arms keep the same latest-non-failed
-- run, the enriched INNER JOIN video_rag gate, and the failure_count ceiling, and
-- return the same columns (the gym grouping + the run row's video_run_id the verdict
-- UPDATE keys on + the fields the scan prompt shows). The scan is TEXT-ONLY: the
-- enrich step already did the multimodal (thumbnail) pass and folded the visual
-- detail into the summary, so the judge reads the summary + the structured enrich
-- outputs (genre, disciplines, facets) and never re-fetches the thumbnail.
WITH latest_run AS (
    SELECT DISTINCT ON (gym_id) gym_id, run_id
    FROM video_run
    WHERE status <> 'failed'
    ORDER BY gym_id, created_at DESC
)
SELECT
    lr.gym_id,
    f.video_run_id,
    v.video_id,
    v.title,
    v.channel_name,
    v.tag AS genre,
    v.disciplines,
    r.summary,
    r.facets
FROM gym_video_feed f
JOIN latest_run lr ON lr.run_id = f.video_run_id
JOIN video v ON v.video_id = f.video_id
JOIN video_rag r ON r.video_id = v.video_id
WHERE v.failure_count < :max_failures
  AND (
      f.scan_status = 'pending'
      OR (
          f.curation_type = 'automatic'
          AND EXISTS (
              SELECT 1
              FROM gym_video_spec s
              WHERE s.gym_id = lr.gym_id
                AND s.source = 'feed_update'
                AND s.created_at > COALESCE(f.scanned_at, '-infinity'::timestamptz)
                AND s.created_at <= now()
                    - make_interval(hours => :rescan_delay_hours)
          )
      )
  )
ORDER BY lr.gym_id, v.relevance_index, v.video_id;
