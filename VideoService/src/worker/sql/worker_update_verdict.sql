-- Write ONE scan verdict onto an AUTO-curated feed row: flip scan_status to
-- accepted/rejected. The curation_type <> 'manual' guard means an owner's explicit
-- keep/reject is NEVER overwritten — but an automatic row (whether still 'pending'
-- for its first verdict, OR already accepted/rejected and being RE-SCANNED against
-- a new feed_update spec) IS re-judged, flipping accepted<->rejected only when the
-- judgment changes. curation_type stays 'automatic'. A rejected row stamps
-- rejected_at (now() from the caller, NULL for accepted). scanned_at = now() marks
-- this row as judged so the same feed_update never re-triggers it. Keyed by
-- (gym_id, video_id, video_run_id) so it targets exactly this run's row. Runs once
-- per verdicted video (executemany).
UPDATE gym_video_feed
   SET scan_status = CAST(:verdict AS gym_video_scan_status),
       rejected_at = :rejected_at,
       scanned_at = now()
 WHERE gym_id = CAST(:gym_id AS UUID)
   AND video_id = :video_id
   AND video_run_id = CAST(:video_run_id AS UUID)
   AND curation_type <> 'manual';
