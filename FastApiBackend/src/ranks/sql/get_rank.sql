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
WHERE rank_id = CAST(:rank_id AS UUID)
