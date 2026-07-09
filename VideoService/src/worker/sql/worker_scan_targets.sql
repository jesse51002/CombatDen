-- The scan sweep's target set (gym-agnostic, grouped by gym): the 'pending' feed
-- rows in each gym's LATEST NON-FAILED run whose video is ALREADY enriched (a
-- video_rag row exists) and is under the strike ceiling. Returns the gym grouping
-- + the run row's video_run_id (the verdict UPDATE keys on it) + the fields the
-- scan prompt shows. The scan is TEXT-ONLY: the enrich step already did the
-- multimodal (thumbnail) pass and folded the visual detail into the summary, so
-- the judge reads the summary + the structured enrich outputs (genre, disciplines,
-- facets) and never re-fetches the thumbnail. Only 'pending' rows are targets: an
-- accepted/rejected row is terminal (a manual or prior automatic verdict), never
-- re-judged. Same latest-non-failed-run logic as the enrich sweep.
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
WHERE f.scan_status = 'pending'
  AND v.failure_count < :max_failures
ORDER BY lr.gym_id, v.relevance_index, v.video_id;
