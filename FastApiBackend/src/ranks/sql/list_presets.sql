SELECT
    preset_id,
    gym_type,
    main_rank_num_order,
    sub_rank_num_order,
    main_name,
    sub_name,
    classes_till_rankup,
    image_url,
    color
FROM rank_presets
WHERE gym_type = :gym_type
ORDER BY main_rank_num_order ASC, sub_rank_num_order ASC
