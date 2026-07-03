-- The member facts a v1 deterministic profile template is built from, in one
-- round-trip (scalar subqueries keyed on the member):
--   gym_id                           the member's OWN gym — the caller must
--                                    verify this matches the gym it's asking
--                                    about before using anything else here.
--   rank_main_name / rank_sub_name  the member's current rank names (NULL when
--                                    members.current_rank_id is NULL).
--   attendance_count                 number of class check-ins in the trailing
--                                    window (:window_days).
--   last_attended_at                 most-recent occurred_at in that window
--                                    (NULL when there is none).
--   top_classes                      up to 3 most-attended class names in the
--                                    window, most-frequent first (JSONB array).
--   disciplines                      the gym's discipline list from its LATEST
--                                    video spec (gym_video_spec_latest.gym_type,
--                                    a JSONB string array); NULL when no spec.
SELECT
    m.gym_id,
    r.main_name AS rank_main_name,
    r.sub_name AS rank_sub_name,
    (
        SELECT count(*)
        FROM member_attendance a
        WHERE a.member_id = m.member_id
          AND a.occurred_at >= now() - (:window_days * INTERVAL '1 day')
    ) AS attendance_count,
    (
        SELECT max(a.occurred_at)
        FROM member_attendance a
        WHERE a.member_id = m.member_id
          AND a.occurred_at >= now() - (:window_days * INTERVAL '1 day')
    ) AS last_attended_at,
    (
        SELECT COALESCE(jsonb_agg(t.class_name), '[]'::jsonb)
        FROM (
            SELECT gc.class_name, count(*) AS cnt
            FROM member_attendance a
            JOIN gym_classes gc ON gc.class_id = a.class_id
            WHERE a.member_id = m.member_id
              AND a.occurred_at >= now() - (:window_days * INTERVAL '1 day')
            GROUP BY gc.class_name
            ORDER BY cnt DESC, gc.class_name
            LIMIT 3
        ) t
    ) AS top_classes,
    (
        SELECT gvs.gym_type
        FROM gym_video_spec_latest gvs
        WHERE gvs.gym_id = m.gym_id
    ) AS disciplines
FROM members m
LEFT JOIN gym_ranks r ON r.rank_id = m.current_rank_id
WHERE m.member_id = CAST(:member_id AS UUID)
