-- The member facts the LLM profile-summary prompt is built from, in one
-- round-trip. The prompt degrades to classes + rank + disciplines when the
-- member has no clicks yet (member_activities 'video_clicked').
--   gym_id            the member's OWN gym (also re-checked by the caller).
--   rank_name         the member's current rank name (NULL when unranked).
--   disciplines       the gym's discipline list from its latest video spec
--                     (gym_video_spec_latest.gym_type, a JSONB string array).
--   attended_classes  up to :class_limit most-attended class names in the
--                     trailing :window_days window, most-frequent first (JSONB).
--   clicked_videos    up to :click_limit most-recently-clicked videos'
--                     {title, summary}, newest first (JSONB array of objects).
--                     BOTH click writers land here and are read identically --
--                     the rec the app served (VideoRecClickService, one row per
--                     served rec) and a video the member picked out of the feed
--                     (VideoClickService, one row per open, never deduped). The
--                     join reads activity_info ->> 'video_id' only, so the NULL
--                     rec_id a feed click carries is irrelevant to it.
SELECT
    m.gym_id,
    r.name AS rank_name,
    (
        SELECT gvs.gym_type
        FROM gym_video_spec_latest gvs
        WHERE gvs.gym_id = m.gym_id
    ) AS disciplines,
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
            LIMIT :class_limit
        ) t
    ) AS attended_classes,
    (
        SELECT COALESCE(
            jsonb_agg(
                jsonb_build_object('title', c.title, 'summary', c.summary)
                ORDER BY c.clicked_time DESC
            ),
            '[]'::jsonb
        )
        FROM (
            SELECT v.title AS title, rag.summary AS summary, act.time AS clicked_time
            FROM member_activities act
            JOIN video v ON v.video_id = act.activity_info->>'video_id'
            LEFT JOIN video_rag rag ON rag.video_id = v.video_id
            WHERE act.member_id = m.member_id
              AND act.activity_type = 'video_clicked'
            ORDER BY act.time DESC
            LIMIT :click_limit
        ) c
    ) AS clicked_videos
FROM members m
LEFT JOIN gym_ranks r ON r.rank_id = m.current_rank_id
WHERE m.member_id = CAST(:member_id AS UUID)
