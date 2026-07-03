-- Write the enrich verdict's genre + disciplines onto the pool video. These are
-- the two fields the enrich stage owns (the scrape upsert deliberately preserves
-- them). Runs once per enriched video (executemany).
UPDATE video
   SET tag = CAST(:tag AS video_genre),
       disciplines = CAST(:disciplines AS JSONB)
 WHERE video_id = :video_id;
