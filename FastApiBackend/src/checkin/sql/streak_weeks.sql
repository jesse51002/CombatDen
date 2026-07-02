-- Distinct gym-local weeks (Monday-start) a member has attended a class in.
-- Weeks are bucketed in the GYM's CURRENT timezone, not UTC/session TZ --
-- streak bucketing is a live gamification convention, not occurrence
-- identity, so it reads gyms.timezone as-is rather than any frozen
-- per-version zone. Convert occurred_at (a timestamptz) to gym-local wall
-- clock first, then truncate -- otherwise a late-evening gym-local class
-- near midnight UTC would bucket into the wrong week.
SELECT DISTINCT
    date_trunc('week', ma.occurred_at AT TIME ZONE g.timezone)::date
        AS week_start
FROM member_attendance ma
JOIN gyms g ON g.gym_id = ma.gym_id
WHERE ma.member_id = :member_id
  AND ma.gym_id = :gym_id
ORDER BY week_start DESC
