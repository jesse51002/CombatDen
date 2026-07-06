-- The "ready to promote" board: ranked, active-membership (not frozen),
-- not-top-of-ladder members ordered by how close they are to their next
-- leaf. classes_since is attendance since the member's last rank change
-- (the member_details.sql progress anchor, reused verbatim); the step
-- denominator is an even split of classes_to_next_major across the
-- sub-positions (ceil), or the full major threshold when the rank has no
-- sub-ranks. The service derives each row's sub_label from the gym's
-- sub_rank_type + current_sub_index.
WITH ready AS (
    SELECT
        m.member_id,
        m.first_name || ' ' || m.last_name AS name,
        m.photo_url AS avatar_url,
        gr.rank_id AS main_rank_id,
        gr.name AS main_name,
        m.current_sub_index,
        gr.image_url,
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
            WHEN gr.sub_rank_count > 0
                THEN CEIL(gr.classes_to_next_major::numeric / gr.sub_rank_count)::int
            ELSE NULLIF(gr.classes_to_next_major, 0)
        END AS step_denominator
    FROM members m
    JOIN gym_ranks gr
        ON m.current_rank_id = gr.rank_id
        AND m.gym_id = gr.gym_id
    WHERE m.gym_id = CAST(:gym_id AS UUID)
      AND m.current_rank_id IS NOT NULL
      AND EXISTS (
          SELECT 1
          FROM member_memberships_status mm
          WHERE mm.member_id = m.member_id
            AND mm.gym_id = m.gym_id
            AND mm.status = 'active'
      )
      AND NOT (
          gr.main_rank_num_order = (
              SELECT MAX(main_rank_num_order)
              FROM gym_ranks
              WHERE gym_id = CAST(:gym_id AS UUID)
          )
          AND (
              gr.sub_rank_count = 0
              OR m.current_sub_index = gr.sub_rank_count - 1
          )
      )
)
SELECT
    member_id,
    name,
    avatar_url,
    main_rank_id,
    main_name,
    current_sub_index,
    image_url,
    classes_since,
    step_denominator,
    COUNT(*) OVER() AS total_count
FROM ready
WHERE step_denominator IS NOT NULL
ORDER BY
    (classes_since::numeric / step_denominator) DESC NULLS LAST,
    classes_since DESC
LIMIT :count OFFSET :start_index
