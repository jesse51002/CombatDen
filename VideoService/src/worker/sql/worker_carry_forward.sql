-- Carry the previous completed run's feed rows into THIS run, preserving each
-- row's full curation state. The {manual_only} structural clause selects the
-- mode:
--   * incremental (criteria unchanged) -> '' : copy ALL prior rows (their
--     automatic + manual verdicts stand; only new/changed videos were rescanned).
--   * fresh (criteria changed)          -> "AND curation_type = 'manual'" : copy
--     ONLY the owner's manual verdicts (they are permanent); every automatic
--     verdict is recomputed by this run's fresh scan.
-- Runs BEFORE the scan-verdict insert, so a carried row wins the ON CONFLICT
-- there (carried rows always beat a fresh automatic verdict for the same video).
-- scanned_at is carried FORWARD too (the scan watermark): without it every
-- carried automatic row lands with scanned_at=NULL and the scan sweep's arm B
-- re-matches the ENTIRE carried feed against an already-consumed feed_update on
-- the next run (re-judging + re-embedding + re-paying the scan LLM for the whole
-- feed). Preserving it keeps the "already judged against this feed_update" mark.
INSERT INTO gym_video_feed (
    gym_id, video_id, video_run_id, scan_status,
    curation_type, curation_reason, curated_at, rejected_at, scanned_at
)
SELECT
    gym_id, video_id, CAST(:new_run_id AS UUID), scan_status,
    curation_type, curation_reason, curated_at, rejected_at, scanned_at
FROM gym_video_feed
WHERE video_run_id = CAST(:prev_run_id AS UUID)
      {manual_only}
ON CONFLICT (video_run_id, video_id)
    WHERE video_run_id IS NOT NULL DO NOTHING;
