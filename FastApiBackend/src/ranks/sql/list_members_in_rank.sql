-- Members currently on one MAIN rank, ordered by PERCENTAGE complete
-- toward the next leaf (proportionally closest first — 30/40 outranks
-- 1/10), the same order as the ready-to-promote board; all members
-- returned. classes_since is the same progress anchor as
-- member_details.sql (attendance since the last rank change);
-- step_denominator is the even-split classes-to-next-leaf (ceil) or the
-- full major threshold when the rank has no sub-ranks. The EFFECTIVE
-- sub-rank count is 0 whenever the gym's sub_rank_type is 'none' (sub-ranks
-- disabled gym-wide), so the step is the full major threshold there. Unlike
-- the ready board, EVERY member on the rank is returned — there is NO
-- membership / top-of-ladder filter and NO step_denominator IS NOT NULL
-- filter; a member whose step_denominator is NULL (e.g. a top-of-ladder
-- rank with 0 classes_to_next_major) just sorts last via NULLS LAST. The
-- computation is wrapped in a CTE so the percentage expression in ORDER BY
-- can reference classes_since / step_denominator as columns. The service
-- derives each row's sub_label from the gym's sub_rank_type.
WITH in_rank AS (
    SELECT
        m.member_id,
        m.first_name || ' ' || m.last_name AS name,
        m.photo_url AS avatar_url,
        m.current_sub_index,
        (
            SELECT COUNT(ma.log_id)
            FROM member_attendance ma
            WHERE ma.member_id = m.member_id
              AND ma.gym_id = m.gym_id
              AND ma.occurred_at > COALESCE(
                  (
                      SELECT MAX(act.time)
                      FROM member_activities act
                      WHERE act.member_id = m.member_id
                        AND act.gym_id = m.gym_id
                        AND act.activity_type = 'rank_changed'
                  ),
                  m.created_at
              )
        ) AS classes_since,
        CASE
            WHEN (CASE WHEN g.sub_rank_type = 'none'
                       THEN 0 ELSE gr.sub_rank_count END) > 0
                THEN CEIL(
                    gr.classes_to_next_major::numeric
                    / (CASE WHEN g.sub_rank_type = 'none'
                            THEN 0 ELSE gr.sub_rank_count END)
                )::int
            ELSE NULLIF(gr.classes_to_next_major, 0)
        END AS step_denominator
    FROM members m
    JOIN gym_ranks gr
        ON gr.rank_id = m.current_rank_id
        AND gr.gym_id = m.gym_id
    JOIN gyms g
        ON g.gym_id = m.gym_id
    WHERE m.gym_id = CAST(:gym_id AS UUID)
      AND m.current_rank_id = CAST(:rank_id AS UUID)
)
SELECT
    member_id,
    name,
    avatar_url,
    current_sub_index,
    classes_since,
    step_denominator,
    COUNT(*) OVER() AS total_count
FROM in_rank
ORDER BY
    (classes_since::numeric / NULLIF(step_denominator, 0)) DESC NULLS LAST,
    classes_since DESC,
    member_id ASC
LIMIT :count OFFSET :start_index
