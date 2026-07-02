-- Per-membership (item) class usage + coverage, evaluated AT A REFERENCE
-- INSTANT — the occurrence being checked into (:reference_instant, nullable;
-- NULL = now, which reproduces the plain current-cycle read the member-detail
-- usage bridge wants).
--
-- covers_reference: whether the membership was ACTIVE at the reference
-- instant's gym-local date — started on/before it, not ended/cancelled by it,
-- not frozen across it. THE gate predicate for retro check-ins: a trial that
-- ended last week still covers last Tuesday's class; a membership started
-- yesterday does NOT cover it. ms.status stays the NOW-anchored view status
-- (display). Freeze coverage is best-effort: members stores only the
-- current/most recent freeze window, so historical freezes are invisible.
--
-- Usage: counts member_attendance rows (attributed via item_id) whose own
-- occurred_at (the denormalized EFFECTIVE start instant) falls inside the
-- membership's CURRENT billing window [last_paid_date | start_date,
-- next_due_date | today+1) -- read directly off the attendance row, no join.
-- A reference in a PAST billing cycle gets its usage recounted per item by
-- the service (CycleCountsService steps the anchor back by the plan's
-- duration and re-counts via checkin_item_usage_window.sql); duration_amount
-- / duration_unit ride along for exactly that.
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
    ref.ref_date AS reference_date,
    (
        ms.start_date <= ref.ref_date
        AND (ms.cancel_date IS NULL OR ms.cancel_date > ref.ref_date)
        AND (ms.end_date IS NULL OR ms.end_date > ref.ref_date)
        AND NOT (
            ms.freeze_start_date IS NOT NULL
            AND ms.freeze_end_date IS NOT NULL
            AND ms.freeze_start_date <= ref.ref_date
            AND ref.ref_date <= ms.freeze_end_date
        )
    ) AS covers_reference,
    mp.plan_type,
    mp.duration_amount,
    mp.duration_unit,
    mp.class_count * ms.quantity AS class_count,
    COALESCE(counts.classes_used, 0) AS classes_used,
    -- Remaining capacity, clamped at 0 so an over-drawn pack (e.g. forced via an
    -- override check-in) never reports negative. NULL class_count (unlimited)
    -- stays NULL -- a bare GREATEST(NULL - used, 0) would wrongly report 0, so
    -- the NULL case is guarded explicitly.
    CASE
        WHEN mp.class_count IS NULL THEN NULL
        ELSE GREATEST(
            mp.class_count * ms.quantity - COALESCE(counts.classes_used, 0),
            0
        )
    END AS classes_remaining
FROM member_memberships_status ms
JOIN membership_plans mp
    ON  mp.plan_id = ms.plan_id
    AND mp.gym_id  = ms.gym_id
JOIN gyms g
    ON g.gym_id = ms.gym_id
CROSS JOIN LATERAL (
    SELECT (
        COALESCE(CAST(:reference_instant AS TIMESTAMPTZ), now())
        AT TIME ZONE g.timezone
    )::date AS ref_date
) ref
LEFT JOIN (
    SELECT
        ma.item_id,
        COUNT(*) AS classes_used
    FROM member_attendance ma
    -- A no-membership staff check-in carries NULL item_id; that row never
    -- matches an mm.item_id here, so it is naturally excluded from every
    -- membership's cycle count (it draws down no pack).
    JOIN member_memberships_status mm
        ON  mm.item_id = ma.item_id
    JOIN gyms g2 ON g2.gym_id = ma.gym_id
    WHERE ma.gym_id = :gym_id
      AND ma.member_id = ANY(CAST(:member_ids AS uuid[]))
      AND ma.occurred_at >= COALESCE(mm.last_paid_date, mm.start_date)
      AND ma.occurred_at <  COALESCE(
              mm.next_due_date,
              (now() AT TIME ZONE g2.timezone)::date + INTERVAL '1 day'
          )
    GROUP BY ma.item_id
) counts
    ON counts.item_id = ms.item_id
WHERE ms.gym_id = :gym_id
  AND ms.member_id = ANY(CAST(:member_ids AS uuid[]))
