-- Insert one funnel candidate as a PENDING feed row for this run — the scrape
-- step's only feed write besides the carry-forward. scan_status is 'pending' (the
-- enrich + scan sweeps process it later); curation_type is 'automatic'. ON CONFLICT
-- DO NOTHING so a carried-forward row (inserted FIRST, same scrape step) always
-- wins — a carried manual/verdict row is never downgraded to pending. Runs once
-- per candidate (executemany).
INSERT INTO gym_video_feed (
    gym_id, video_id, video_run_id, scan_status, curation_type
)
VALUES (
    CAST(:gym_id AS UUID),
    :video_id,
    CAST(:run_id AS UUID),
    'pending',
    'automatic'
)
ON CONFLICT (video_run_id, video_id)
    WHERE video_run_id IS NOT NULL DO NOTHING;
