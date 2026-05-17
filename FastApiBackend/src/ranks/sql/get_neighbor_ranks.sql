WITH target AS (
    SELECT gym_id, main_rank_num_order, sub_rank_num_order
    FROM gym_ranks
    WHERE rank_id = :rank_id
),
lower_rank AS (
    SELECT r.rank_id
    FROM gym_ranks r, target t
    WHERE r.gym_id = t.gym_id
      AND r.rank_id <> :rank_id
      AND (r.main_rank_num_order, r.sub_rank_num_order)
          < (t.main_rank_num_order, t.sub_rank_num_order)
    ORDER BY r.main_rank_num_order DESC, r.sub_rank_num_order DESC
    LIMIT 1
),
higher_rank AS (
    SELECT r.rank_id
    FROM gym_ranks r, target t
    WHERE r.gym_id = t.gym_id
      AND r.rank_id <> :rank_id
      AND (r.main_rank_num_order, r.sub_rank_num_order)
          > (t.main_rank_num_order, t.sub_rank_num_order)
    ORDER BY r.main_rank_num_order ASC, r.sub_rank_num_order ASC
    LIMIT 1
)
SELECT
    (SELECT gym_id FROM target) AS gym_id,
    (SELECT rank_id FROM lower_rank) AS lower_rank_id,
    (SELECT rank_id FROM higher_rank) AS higher_rank_id
