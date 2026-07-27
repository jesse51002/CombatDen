-- The member's rank-progress series source, in ONE read: the member's
-- CURRENT-rank denominator context (to size "classes needed to the next rank")
-- plus the chronological stream of their rank_changed + class_attended activity
-- events. The service walks the events in Python — a rank_changed (promotion)
-- resets the running count to 0, a class_attended increments it by one capped
-- at classes_needed.
--
-- A single-row member context CTE LEFT JOINed to the activity stream, so the
-- constant rank/denominator columns ride every activity row AND a member with
-- NO activities still returns one context row (letting the service detect "no
-- rank" / "ranks disabled" and return an empty series). video_clicked
-- activities are excluded by the activity_type filter on the join.
--
-- Dates are bucketed in the gym's OWN timezone (matching member_details /
-- streak), so a point's date is the gym-local day the event happened.
WITH member_ctx AS (
    SELECT
        m.current_rank_id,
        g.is_rank_enabled,
        g.sub_rank_type,
        g.timezone,
        gr.classes_to_next_major,
        gr.sub_rank_count
    FROM members m
    JOIN gyms g ON g.gym_id = m.gym_id
    LEFT JOIN gym_ranks gr
        ON gr.rank_id = m.current_rank_id
       AND gr.gym_id = m.gym_id
    WHERE m.member_id = CAST(:member_id AS UUID)
      AND m.gym_id = CAST(:gym_id AS UUID)
)
SELECT
    ctx.current_rank_id,
    ctx.is_rank_enabled,
    ctx.sub_rank_type,
    ctx.classes_to_next_major,
    ctx.sub_rank_count,
    act.activity_type,
    (act.time AT TIME ZONE ctx.timezone)::date AS activity_date
FROM member_ctx ctx
LEFT JOIN member_activities act
    ON act.member_id = CAST(:member_id AS UUID)
   AND act.gym_id = CAST(:gym_id AS UUID)
   AND act.activity_type IN ('rank_changed', 'class_attended')
ORDER BY act.time ASC, act.activity_id ASC;
