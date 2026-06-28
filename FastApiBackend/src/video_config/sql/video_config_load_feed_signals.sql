-- Unconsumed manual curation signals for a gym: feed rows the owner manually
-- touched (curated_at IS NOT NULL) SINCE the gym's last feed_update spec version
-- (the last time the refiner ran). When no feed_update version exists the anchor
-- is -infinity, so ALL manually-curated rows are returned.
--
-- "Unconsumed" means curated after the latest feed_update version was created —
-- those are the signals that spec version hasn't learned from yet.
SELECT
    f.video_id,
    v.title,
    v.channel_name,
    f.scan_status,
    f.rejection_type,
    f.reject_reason,
    f.curated_at
FROM gym_video_feed AS f
JOIN video AS v ON v.video_id = f.video_id
WHERE f.gym_id = CAST(:gym_id AS UUID)
  AND f.curated_at IS NOT NULL
  AND f.curated_at > COALESCE(
      (
          SELECT MAX(created_at)
          FROM gym_video_spec
          WHERE gym_id = CAST(:gym_id AS UUID)
            AND source = 'feed_update'
      ),
      '-infinity'::TIMESTAMPTZ
  )
ORDER BY f.curated_at
