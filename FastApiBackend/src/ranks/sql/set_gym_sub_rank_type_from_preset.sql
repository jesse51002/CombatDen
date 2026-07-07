-- Copy the preset kind's implied sub_rank_type onto the gym. Every kind
-- implies a concrete style now: the stripes preset carries
-- implied_sub_rank_type = 'stripes', the plain-belts / flat presets carry
-- 'none' (main belts, no sub-positions). So a plain-belts preset makes the
-- gym read 'none'. The MAX(...) IS NOT NULL guard is a defensive no-clobber
-- (never write a NULL into the NOT NULL column); it always passes for real
-- preset rows since they all carry a concrete implied type.
UPDATE gyms
SET sub_rank_type = sub.t
FROM (
    SELECT MAX(implied_sub_rank_type) AS t
    FROM rank_presets
    WHERE preset_kind = CAST(:preset_kind AS rank_preset_kind)
) sub
WHERE gym_id = CAST(:gym_id AS UUID)
  AND sub.t IS NOT NULL
