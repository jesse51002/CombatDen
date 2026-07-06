-- Clone every MAIN row of a preset ladder into a gym's gym_ranks.
-- ON CONFLICT (gym_id, main_rank_num_order) DO NOTHING makes re-running
-- on the same gym idempotent. sub_rank_image_overrides starts empty
-- (presets carry only the main image_url).
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
ON CONFLICT (gym_id, main_rank_num_order) DO NOTHING
