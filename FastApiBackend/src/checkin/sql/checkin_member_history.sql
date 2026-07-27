-- A member's class HISTORY, newest first, paginated in SQL (the house
-- rule): every ATTENDED occurrence (their member_attendance rows) plus
-- every NO-SHOW -- a sign-up whose occurrence already ENDED (original slot
-- instant + the current version's duration, in the current version's frozen
-- timezone) with no matching attendance row on the exact original slot.
-- Ended-ness uses the CURRENT version's timezone/duration -- a documented
-- approximation for historical rows (per-occurrence re-times are ignored;
-- fine for a history feed). Ordered by the original slot (identity) so
-- attended and no-show rows interleave deterministically. total_rows
-- (COUNT(*) OVER ()) lets the service derive has_more without a second
-- query.
WITH history AS (
    SELECT
        ma.class_id,
        ma.original_date,
        ma.original_time,
        ma.occurred_at,
        'attended' AS status
    FROM member_attendance ma
    WHERE ma.member_id = CAST(:member_id AS UUID)
      AND ma.gym_id = CAST(:gym_id AS UUID)

    UNION ALL

    SELECT
        cs.class_id,
        cs.original_date,
        cs.original_time,
        CAST(NULL AS TIMESTAMPTZ) AS occurred_at,
        'no_show' AS status
    FROM class_signups cs
    JOIN gym_class_schedules_current s ON s.class_id = cs.class_id
    WHERE cs.member_id = CAST(:member_id AS UUID)
      AND cs.gym_id = CAST(:gym_id AS UUID)
      AND (
          (cs.original_date + cs.original_time) AT TIME ZONE s.timezone
          + make_interval(mins => s.duration_minutes)
      ) <= now()
      AND NOT EXISTS (
          SELECT 1
          FROM member_attendance ma2
          WHERE ma2.member_id = cs.member_id
            AND ma2.class_id = cs.class_id
            AND ma2.original_date = cs.original_date
            AND ma2.original_time = cs.original_time
      )
)
SELECT
    h.class_id,
    c.class_name,
    c.image_url,
    h.original_date,
    h.original_time,
    h.occurred_at,
    h.status,
    s.duration_minutes,
    c.points_worth,
    COUNT(*) OVER () AS total_rows
FROM history h
JOIN gym_classes c ON c.class_id = h.class_id
JOIN gym_class_schedules_current s ON s.class_id = h.class_id
ORDER BY h.original_date DESC, h.original_time DESC
LIMIT :limit OFFSET :offset
