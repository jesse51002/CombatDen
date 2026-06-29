-- Unconsumed manual curation signals for a gym: scan-feed rows the owner
-- manually touched (curation_type = 'manual', video_run_id IS NOT NULL)
-- SINCE the gym's latest spec version of any source. When no spec version
-- exists the anchor is -infinity, so ALL such rows are returned.
--
-- "Unconsumed" means curated after the latest spec version was created —
-- those are signals the spec hasn't yet learned from. The anchor is
-- MAX(created_at) over ALL sources (admin_update, system_update, feed_update)
-- so an owner-authored or preset-imported version also consumes prior curation,
-- preventing the refiner from re-folding signals already addressed.
--
-- Owner "Your videos" rows (video_run_id IS NULL) are excluded: they are
-- custom owner uploads, not scan-feed curation decisions, and must not feed
-- the refiner.
--
-- Joins the shared pool `video` row for title, channel, description, and
-- transcript so the refiner prompt can explain each signal in full context.
-- scan_status tells keep vs reject; curation_reason carries the owner's stated
-- reason (if any). Use CAST(:gym_id AS UUID) — never :gym_id::uuid.
SELECT
    f.video_id,
    v.title,
    v.channel_name,
    v.description,
    v.transcript,
    f.scan_status,
    f.curation_type,
    f.curation_reason,
    f.curated_at
FROM gym_video_feed AS f
JOIN video AS v ON v.video_id = f.video_id
WHERE f.gym_id = CAST(:gym_id AS UUID)
  AND f.curation_type = 'manual'
  AND f.video_run_id IS NOT NULL
  AND f.curated_at > COALESCE(
      (
          SELECT MAX(created_at)
          FROM gym_video_spec
          WHERE gym_id = CAST(:gym_id AS UUID)
      ),
      '-infinity'::TIMESTAMPTZ
  )
ORDER BY f.curated_at
