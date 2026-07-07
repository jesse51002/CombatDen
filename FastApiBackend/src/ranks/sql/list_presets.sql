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
WHERE preset_kind = CAST(:preset_kind AS rank_preset_kind)
ORDER BY main_rank_num_order ASC
