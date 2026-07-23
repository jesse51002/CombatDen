-- Distinct gym-local weekdays (ISO: 1=Mon .. 7=Sun) a member attended a
-- class on in the CURRENT gym-local (Monday-start) week.
--
-- Buckets in the GYM's CURRENT timezone, not UTC/session TZ -- the same
-- live gamification convention as streak_weeks.sql, so it reads
-- gyms.timezone as-is rather than any frozen per-version zone. Convert
-- occurred_at (a timestamptz) to gym-local wall clock first, then truncate
-- to the week and read the weekday -- otherwise a late-evening gym-local
-- class near midnight UTC would land on the wrong day/week.
--
-- The current-week Monday anchor is passed in by the service (a gym-local
-- date), computed from the same gyms.timezone, so the strip and the streak
-- count can never disagree about which week is "current".
SELECT DISTINCT
    EXTRACT(ISODOW FROM ma.occurred_at AT TIME ZONE g.timezone)::int
        AS iso_dow
FROM member_attendance ma
JOIN gyms g ON g.gym_id = ma.gym_id
WHERE ma.member_id = :member_id
  AND ma.gym_id = :gym_id
  AND date_trunc('week', ma.occurred_at AT TIME ZONE g.timezone)::date
      = :current_week_monday
