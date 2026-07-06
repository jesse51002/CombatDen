SELECT
    rank_id,
    gym_id,
    main_rank_num_order,
    name,
    image_url,
    classes_to_next_major,
    sub_rank_count,
    sub_rank_image_overrides,
    created_at
FROM gym_ranks
WHERE gym_id = CAST(:gym_id AS UUID)
ORDER BY main_rank_num_order ASC
