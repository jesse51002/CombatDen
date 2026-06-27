-- Per-membership (item) class usage within the current billing cycle.
-- Counts member_attendance rows (attributed to a specific membership via
-- item_id) whose class_history.occurred_at falls inside that membership's
-- billing window [last_paid_date | start_date, next_due_date | today+1).
-- The allowance is plan.class_count * the membership's quantity: a stacked
-- one_time / trial pack bought N at once is ONE row (quantity = N) granting one
-- combined bucket of class_count * N. NULL class_count (unlimited) stays NULL
-- (NULL * N = NULL). Keyed by item_id so a SEPARATE membership on the same plan
-- (e.g. another pack bought later) still gets its own independent bucket.
SELECT
    ms.member_id,
    ms.item_id,
    ms.plan_id,
    ms.gym_id,
    ms.start_date,
    ms.last_paid_date,
    ms.next_due_date,
    ms.end_date,
    ms.status,
    mp.plan_type,
    mp.class_count * ms.quantity AS class_count,
    COALESCE(counts.classes_used, 0) AS classes_used
FROM member_memberships_status ms
JOIN membership_plans mp
    ON  mp.plan_id = ms.plan_id
    AND mp.gym_id  = ms.gym_id
LEFT JOIN (
    SELECT
        ma.item_id,
        COUNT(*) AS classes_used
    FROM member_attendance ma
    JOIN class_history ch
        ON  ch.class_history_id = ma.class_history_id
    JOIN member_memberships_status mm
        ON  mm.item_id = ma.item_id
    JOIN gyms g2 ON g2.gym_id = ma.gym_id
    WHERE ma.gym_id = :gym_id
      AND ma.member_id = ANY(CAST(:member_ids AS uuid[]))
      AND ch.occurred_at >= COALESCE(mm.last_paid_date, mm.start_date)
      AND ch.occurred_at <  COALESCE(
              mm.next_due_date,
              (now() AT TIME ZONE g2.timezone)::date + INTERVAL '1 day'
          )
    GROUP BY ma.item_id
) counts
    ON counts.item_id = ms.item_id
WHERE ms.gym_id = :gym_id
  AND ms.member_id = ANY(CAST(:member_ids AS uuid[]))
