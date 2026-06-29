-- The video's source (web_query | manual) — decides removal: web_query is
-- rejected (kept), manual is hard-deleted. NULL row when the id isn't pooled.
SELECT added_via FROM video WHERE video_id = :video_id
