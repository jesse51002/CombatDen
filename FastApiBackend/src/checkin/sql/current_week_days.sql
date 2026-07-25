-- Distinct gym-local weekdays (ISO: 1=Mon .. 7=Sun) a member attended a
-- class on in the CURRENT gym-local (Monday-start) week.
--
-- Buckets in the GYM's CURRENT timezone, not UTC -- same live-gamification
-- convention as streak_weeks.sql. occurred_at must be converted to gym-local
-- wall clock BEFORE truncating, or a late-evening class near midnight UTC
-- lands on the wrong day. The Monday anchor is passed in by the service off
-- the same gyms.timezone, so the strip and the streak count cannot disagree
-- about which week is "current".
SELECT DISTINCT
    EXTRACT(ISODOW FROM ma.occurred_at AT TIME ZONE g.timezone)::int
        AS iso_dow
FROM member_attendance ma
JOIN gyms g ON g.gym_id = ma.gym_id
WHERE ma.member_id = :member_id
  AND ma.gym_id = :gym_id
  AND date_trunc('week', ma.occurred_at AT TIME ZONE g.timezone)::date
      = :current_week_monday
