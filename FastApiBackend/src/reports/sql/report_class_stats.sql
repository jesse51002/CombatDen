-- Per-class activity for the report window. Every class of the gym is listed
-- (LEFT JOINs, COALESCE 0) so classes with zero activity still appear. Check-in
-- counts window on member_attendance.occurred_at; sign-up counts window on
-- class_signups.created_at. Classes are not filtered by is_deleted so a class
-- that had activity in a past window still surfaces (is_active / is_deleted are
-- exposed for the reader to filter).
SELECT
    gc.class_id,
    gc.class_name,
    gc.is_active,
    gc.is_deleted,
    COALESCE(att.check_in_count, 0) AS check_in_count,
    COALESCE(att.distinct_members, 0) AS distinct_members,
    COALESCE(su.signup_count, 0) AS signup_count
FROM gym_classes gc
LEFT JOIN (
    SELECT
        a.class_id,
        COUNT(*) AS check_in_count,
        COUNT(DISTINCT a.member_id) AS distinct_members
    FROM member_attendance a
    WHERE a.gym_id = CAST(:gym_id AS UUID)
      AND (
          CAST(:all_time AS BOOLEAN)
          OR (
              a.occurred_at >= CAST(:start_utc AS TIMESTAMPTZ)
              AND a.occurred_at < CAST(:end_utc AS TIMESTAMPTZ)
          )
      )
    GROUP BY a.class_id
) att ON att.class_id = gc.class_id
LEFT JOIN (
    SELECT
        s.class_id,
        COUNT(*) AS signup_count
    FROM class_signups s
    WHERE s.gym_id = CAST(:gym_id AS UUID)
      AND (
          CAST(:all_time AS BOOLEAN)
          OR (
              s.created_at >= CAST(:start_utc AS TIMESTAMPTZ)
              AND s.created_at < CAST(:end_utc AS TIMESTAMPTZ)
          )
      )
    GROUP BY s.class_id
) su ON su.class_id = gc.class_id
WHERE gc.gym_id = CAST(:gym_id AS UUID)
ORDER BY gc.class_name ASC, gc.class_id ASC
