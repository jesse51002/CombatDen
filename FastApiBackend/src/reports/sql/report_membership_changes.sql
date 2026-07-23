-- Membership movement in the report window: one row per lifecycle event
-- (started | cancelled | ended), UNIONed. Reads the filtered member_memberships
-- view (matches the CRM screens). The window compares the DATE columns to the
-- gym-local period dates (start/end are DATE, no timezone). The started arm's
-- window is the only one that also honours the all-time flag directly; the
-- cancelled/ended arms first require the date to exist, then apply the same
-- windowed-or-all-time predicate. member + plan names come from the filtered
-- membership_plans view.
WITH changes AS (
    SELECT
        mm.start_date AS change_date,
        'started' AS change_type,
        mm.item_id,
        mm.member_id,
        mm.plan_id
    FROM member_memberships mm
    WHERE mm.gym_id = CAST(:gym_id AS UUID)
      AND (
          CAST(:all_time AS BOOLEAN)
          OR (
              mm.start_date >= CAST(:start_local AS DATE)
              AND mm.start_date < CAST(:end_local AS DATE)
          )
      )
    UNION ALL
    SELECT
        mm.cancel_date AS change_date,
        'cancelled' AS change_type,
        mm.item_id,
        mm.member_id,
        mm.plan_id
    FROM member_memberships mm
    WHERE mm.gym_id = CAST(:gym_id AS UUID)
      AND mm.cancel_date IS NOT NULL
      AND (
          CAST(:all_time AS BOOLEAN)
          OR (
              mm.cancel_date >= CAST(:start_local AS DATE)
              AND mm.cancel_date < CAST(:end_local AS DATE)
          )
      )
    UNION ALL
    SELECT
        mm.end_date AS change_date,
        'ended' AS change_type,
        mm.item_id,
        mm.member_id,
        mm.plan_id
    FROM member_memberships mm
    WHERE mm.gym_id = CAST(:gym_id AS UUID)
      AND mm.end_date IS NOT NULL
      AND (
          CAST(:all_time AS BOOLEAN)
          OR (
              mm.end_date >= CAST(:start_local AS DATE)
              AND mm.end_date < CAST(:end_local AS DATE)
          )
      )
)
SELECT
    ch.change_date,
    ch.change_type,
    ch.item_id,
    ch.member_id,
    m.first_name AS member_first_name,
    m.last_name AS member_last_name,
    ch.plan_id,
    p.plan_name
FROM changes ch
LEFT JOIN members m
    ON m.member_id = ch.member_id
   AND m.gym_id = CAST(:gym_id AS UUID)
LEFT JOIN membership_plans p
    ON p.plan_id = ch.plan_id
   AND p.gym_id = CAST(:gym_id AS UUID)
ORDER BY ch.change_date ASC, ch.change_type ASC, ch.item_id ASC
