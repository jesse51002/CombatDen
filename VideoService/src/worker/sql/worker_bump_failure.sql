-- Bump the hard-error strike counter on one video: a multimodal enrich call, an
-- embed call, or a scan batch call raised. The cleanup step deletes the video once
-- failure_count reaches the ceiling. A missing transcript is NOT a strike (it
-- degrades to a placeholder); only a raised call bumps here. Runs once per struck
-- video (executemany).
UPDATE video
   SET failure_count = failure_count + 1
 WHERE video_id = :video_id;
