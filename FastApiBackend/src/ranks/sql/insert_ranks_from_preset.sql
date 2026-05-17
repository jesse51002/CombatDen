INSERT INTO gym_ranks (
    gym_id,
    main_rank_num_order,
    sub_rank_num_order,
    main_name,
    sub_name,
    classes_till_rankup,
    image_url,
    color
)
SELECT
    :gym_id,
    main_rank_num_order,
    sub_rank_num_order,
    main_name,
    sub_name,
    classes_till_rankup,
    image_url,
    color
FROM rank_presets
WHERE gym_type = :gym_type
ON CONFLICT (gym_id, main_rank_num_order, sub_rank_num_order) DO NOTHING
