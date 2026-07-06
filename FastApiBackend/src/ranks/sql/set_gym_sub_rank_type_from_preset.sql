-- Copy the preset kind's implied sub_rank_type onto the gym. A stripes
-- preset carries implied_sub_rank_type = 'stripes' on its rows; a flat
-- preset carries NULL, in which case the gym's existing type is left
-- untouched (the outer guard MAX(...) IS NOT NULL).
UPDATE gyms
SET sub_rank_type = sub.t
FROM (
    SELECT MAX(implied_sub_rank_type) AS t
    FROM rank_presets
    WHERE preset_kind = CAST(:preset_kind AS rank_preset_kind)
) sub
WHERE gym_id = CAST(:gym_id AS UUID)
  AND sub.t IS NOT NULL
