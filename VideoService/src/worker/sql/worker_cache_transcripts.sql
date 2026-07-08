-- Cache a lazily-fetched transcript onto its pool video so a later run reuses it
-- instead of re-paying Apify. Only ever called with a transcript we just fetched
-- (non-null), for a video whose row had none; clears any prior transcript_error.
-- Runs once per fetched video (executemany).
UPDATE video
   SET transcript = :transcript,
       transcript_error = NULL
 WHERE video_id = :video_id;
