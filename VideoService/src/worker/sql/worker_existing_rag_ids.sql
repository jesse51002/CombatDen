-- Which of the given ids are ALREADY enriched (have a video_rag row) — subtracted
-- from the enrich set so a video is embedded at most once. Tier-2 candidates are
-- necessarily already here (that is how the probe found them).
SELECT video_id
FROM video_rag
WHERE video_id = ANY(:ids);
