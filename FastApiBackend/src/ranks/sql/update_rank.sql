-- {set_clause} is built in Python with PER-COLUMN casts: the JSONB
-- overrides column binds as CAST(:sub_rank_image_overrides AS JSONB),
-- every other column as a plain :col (never :col::type — the asyncpg
-- bind bug). sub_rank_count is user-writable; shrinking it clamps
-- members in the same transaction but never prunes the overrides map.
UPDATE gym_ranks
SET {set_clause}
WHERE rank_id = CAST(:rank_id AS UUID)
RETURNING
    rank_id,
    gym_id,
    main_rank_num_order,
    name,
    image_url,
    classes_to_next_major,
    sub_rank_count,
    sub_rank_image_overrides,
    created_at
