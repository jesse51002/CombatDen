-- The candidates that are ready to scan: those with a video_rag row (enriched),
-- joined to the fields the scan prompt shows per video. A candidate missing a
-- row (its enrich call failed) simply does not come back — it is not scanned.
SELECT
    v.video_id,
    v.title,
    v.channel_name,
    v.tag AS genre,
    r.summary
FROM video v
JOIN video_rag r ON r.video_id = v.video_id
WHERE v.video_id = ANY(:ids);
