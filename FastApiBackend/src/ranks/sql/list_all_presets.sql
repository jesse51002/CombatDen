SELECT
    preset_id,
    preset_kind,
    main_rank_num_order,
    name,
    image_url,
    classes_to_next_major,
    sub_rank_count,
    implied_sub_rank_type
FROM rank_presets
ORDER BY preset_kind ASC,
         main_rank_num_order ASC
