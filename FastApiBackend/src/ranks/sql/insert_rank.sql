INSERT INTO gym_ranks (
    gym_id,
    main_rank_num_order,
    name,
    image_url,
    classes_to_next_major,
    sub_rank_count,
    sub_rank_image_overrides
)
VALUES (
    CAST(:gym_id AS UUID),
    :main_rank_num_order,
    :name,
    :image_url,
    :classes_to_next_major,
    :sub_rank_count,
    CAST(:sub_rank_image_overrides AS JSONB)
)
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
