-- Neighbor resolution for a whole-group delete: the replacement for
-- members on ANY sub-rank of the group is the nearest LOWER group's
-- highest sub-rank, else the nearest HIGHER group's lowest sub-rank
-- (mirrors get_neighbor_ranks.sql at group granularity). The final
-- SELECT always yields one row; gym_id is NULL when the group has no
-- rows (caller maps that to not-found).
WITH target AS (
    SELECT gym_id, main_rank_num_order
    FROM gym_ranks
    WHERE gym_id = :gym_id
      AND main_rank_num_order = :main_rank_num_order
    LIMIT 1
),
lower_rank AS (
    SELECT r.rank_id
    FROM gym_ranks r, target t
    WHERE r.gym_id = t.gym_id
      AND r.main_rank_num_order < t.main_rank_num_order
    ORDER BY r.main_rank_num_order DESC, r.sub_rank_num_order DESC
    LIMIT 1
),
higher_rank AS (
    SELECT r.rank_id
    FROM gym_ranks r, target t
    WHERE r.gym_id = t.gym_id
      AND r.main_rank_num_order > t.main_rank_num_order
    ORDER BY r.main_rank_num_order ASC, r.sub_rank_num_order ASC
    LIMIT 1
)
SELECT
    (SELECT gym_id FROM target) AS gym_id,
    (SELECT rank_id FROM lower_rank) AS lower_rank_id,
    (SELECT rank_id FROM higher_rank) AS higher_rank_id
