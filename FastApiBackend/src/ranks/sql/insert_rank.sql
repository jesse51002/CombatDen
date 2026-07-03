-- image_url is deliberately not inserted here: rank images are
-- generation-owned (theme-styled belt art written by the image
-- pipeline), never provided by the create request.
INSERT INTO gym_ranks (
    gym_id,
    main_rank_num_order,
    sub_rank_num_order,
    main_name,
    sub_name,
    classes_till_rankup,
    color
)
VALUES (
    :gym_id,
    :main_rank_num_order,
    :sub_rank_num_order,
    :main_name,
    :sub_name,
    :classes_till_rankup,
    :color
)
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
