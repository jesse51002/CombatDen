SELECT
    rank_id,
    gym_id,
    main_rank_num_order,
    sub_rank_num_order,
    main_name,
    sub_name,
    classes_till_rankup,
    image_url,
    color,
    created_at
FROM gym_ranks
WHERE gym_id = :gym_id
ORDER BY main_rank_num_order ASC, sub_rank_num_order ASC
