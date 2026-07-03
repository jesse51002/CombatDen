-- Which of the freshly-scraped ids already exist in the pool — so the scrape can
-- count NEW vs updated rows without a per-row RETURNING (the upsert runs as one
-- executemany).
SELECT video_id
FROM video
WHERE video_id = ANY(:ids);
