-- Neighbor resolution for a single-rank delete: the replacement for
-- members on this rank is the nearest LOWER main rank, else the nearest
-- HIGHER main rank. One row per MAIN rank now, so ordering is main-only.
-- The final SELECT always yields one row; gym_id is NULL when the rank
-- id doesn't exist (caller maps that to not-found).
WITH target AS (
    SELECT gym_id, main_rank_num_order
    FROM gym_ranks
    WHERE rank_id = CAST(:rank_id AS UUID)
),
lower_rank AS (
    SELECT r.rank_id
    FROM gym_ranks r, target t
    WHERE r.gym_id = t.gym_id
      AND r.rank_id <> CAST(:rank_id AS UUID)
      AND r.main_rank_num_order < t.main_rank_num_order
    ORDER BY r.main_rank_num_order DESC
    LIMIT 1
),
higher_rank AS (
    SELECT r.rank_id
    FROM gym_ranks r, target t
    WHERE r.gym_id = t.gym_id
      AND r.rank_id <> CAST(:rank_id AS UUID)
      AND r.main_rank_num_order > t.main_rank_num_order
    ORDER BY r.main_rank_num_order ASC
    LIMIT 1
)
SELECT
    (SELECT gym_id FROM target) AS gym_id,
    (SELECT rank_id FROM lower_rank) AS lower_rank_id,
    (SELECT rank_id FROM higher_rank) AS higher_rank_id
