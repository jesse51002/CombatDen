-- Rank Distribution (breakdown, count) - how many members sit at each MAIN
-- rank of the gym's ladder, in ladder order (gym_ranks.main_rank_num_order).
--
-- The WHOLE ladder is emitted, including ranks nobody holds: an empty rung is
-- itself the signal (a white belt with no one on it means intake stopped), and
-- a breakdown with gaps would be unreadable against the ladder it mirrors.
--
-- Members whose current_rank_id is NULL are EXCLUDED - they have not been
-- placed on the ladder at all, so they belong to no rung; counting them would
-- need a synthetic "unranked" bucket that is not part of the ladder.
--
-- Sub-ranks (members.current_sub_index) are deliberately not split out: this
-- is one row per MAIN rank, matching the one-row-per-main-rank table.
--
-- color_hint is left unset on purpose. gym_ranks carries a belt IMAGE
-- (image_url), not a hex colour, and the field is a colour hint - deriving one
-- from an image name would be invention.
SELECT jsonb_build_object(
    'unit', 'count',
    'items', COALESCE(
        (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'key', CAST(t.rank_id AS TEXT),
                    'label', t.name,
                    'value', t.member_count
                )
                ORDER BY t.main_rank_num_order
            )
            FROM (
                SELECT
                    r.rank_id,
                    r.name,
                    r.main_rank_num_order,
                    count(m.member_id)::bigint AS member_count
                FROM gym_ranks r
                LEFT JOIN members m
                    ON m.current_rank_id = r.rank_id
                   AND m.gym_id = r.gym_id
                WHERE r.gym_id = CAST(:gym_id AS UUID)
                GROUP BY r.rank_id, r.name, r.main_rank_num_order
            ) t
        ),
        '[]'::jsonb
    )
) AS data
