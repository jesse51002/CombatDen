-- Per-membership class usage within the current billing cycle.
-- Counts member_attendance rows (attributed to a plan via plan_id) whose
-- class_history.occurred_at falls inside the membership's billing window
-- [last_paid_date | start_date, next_due_date | today+1).
SELECT
    ms.member_id,
    ms.plan_id,
    ms.gym_id,
    ms.last_paid_date,
    ms.next_due_date,
    ms.end_date,
    ms.status,
    mp.plan_type,
    mp.class_count,
    COALESCE(counts.classes_used, 0) AS classes_used
FROM member_memberships_status ms
JOIN membership_plans mp
    ON  mp.plan_id = ms.plan_id
    AND mp.gym_id  = ms.gym_id
LEFT JOIN (
    SELECT
        ma.member_id,
        ma.plan_id,
        ma.gym_id,
        COUNT(*) AS classes_used
    FROM member_attendance ma
    JOIN class_history ch
        ON  ch.class_history_id = ma.class_history_id
    JOIN member_memberships_status mm
        ON  mm.member_id = ma.member_id
        AND mm.gym_id    = ma.gym_id
        AND mm.plan_id   = ma.plan_id
    JOIN gyms g2 ON g2.gym_id = ma.gym_id
    WHERE ma.gym_id = :gym_id
      AND ma.member_id = ANY(CAST(:member_ids AS uuid[]))
      AND ch.occurred_at >= COALESCE(mm.last_paid_date, mm.start_date)
      AND ch.occurred_at <  COALESCE(
              mm.next_due_date,
              (now() AT TIME ZONE g2.timezone)::date + INTERVAL '1 day'
          )
    GROUP BY ma.member_id, ma.plan_id, ma.gym_id
) counts
    ON  counts.member_id = ms.member_id
    AND counts.plan_id   = ms.plan_id
    AND counts.gym_id    = ms.gym_id
WHERE ms.gym_id = :gym_id
  AND ms.member_id = ANY(CAST(:member_ids AS uuid[]))
