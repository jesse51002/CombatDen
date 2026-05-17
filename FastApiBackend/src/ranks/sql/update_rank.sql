UPDATE gym_ranks
SET {set_clause}
WHERE rank_id = :rank_id
RETURNING
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
