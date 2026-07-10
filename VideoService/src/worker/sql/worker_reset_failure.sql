-- Reset the strike counter to 0 after a video enriches or gets a scan verdict
-- successfully — the earlier failures were transient, so it should not carry
-- accumulated strikes toward the cleanup ceiling. Runs once per healed video
-- (executemany).
UPDATE video
   SET failure_count = 0
 WHERE video_id = :video_id;
