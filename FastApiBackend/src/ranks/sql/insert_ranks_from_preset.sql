-- Upsert every MAIN row of a preset ladder into a gym: creates missing
-- ladder positions AND overwrites existing ones' name / image_url /
-- sub_rank_count to match the preset. classes_to_next_major and
-- sub_rank_image_overrides are deliberately preserved. Never deletes a
-- rank (positions beyond the preset stay).
INSERT INTO gym_ranks (
    gym_id,
    main_rank_num_order,
    name,
    image_url,
    classes_to_next_major,
    sub_rank_count
)
SELECT
    CAST(:gym_id AS UUID),
    main_rank_num_order,
    name,
    image_url,
    classes_to_next_major,
    sub_rank_count
FROM rank_presets
WHERE preset_kind = CAST(:preset_kind AS rank_preset_kind)
ON CONFLICT (gym_id, main_rank_num_order) DO UPDATE SET
    name = EXCLUDED.name,
    image_url = EXCLUDED.image_url,
    sub_rank_count = EXCLUDED.sub_rank_count
