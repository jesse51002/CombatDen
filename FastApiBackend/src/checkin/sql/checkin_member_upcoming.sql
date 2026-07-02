-- A member's OPEN reservations: sign-ups whose occurrence hasn't ENDED yet
-- (original slot instant + the current version's duration, in the current
-- version's frozen timezone, still ahead of now). "Past means ended, not
-- started" -- an in-session reservation is still upcoming, not yet a
-- no-show. Exact for upcoming rows by construction: the mint wipe keeps
-- future sign-ups only when the CURRENT version still emits their exact
-- slot, so the current version's timezone/duration are authoritative here.
-- Soonest first; unpaginated (a member holds few open reservations).
SELECT
    cs.class_id,
    c.class_name,
    c.image_url,
    cs.original_date,
    cs.original_time,
    s.duration_minutes,
    CAST(NULL AS TIMESTAMPTZ) AS occurred_at
FROM class_signups cs
JOIN gym_classes c ON c.class_id = cs.class_id
JOIN gym_class_schedules_current s ON s.class_id = cs.class_id
WHERE cs.member_id = CAST(:member_id AS UUID)
  AND cs.gym_id = CAST(:gym_id AS UUID)
  AND (
      (cs.original_date + cs.original_time) AT TIME ZONE s.timezone
      + make_interval(mins => s.duration_minutes)
  ) > now()
ORDER BY cs.original_date ASC, cs.original_time ASC
