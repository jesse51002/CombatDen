UPDATE gyms
SET theme_design_id = :theme_design_id
WHERE gym_id = CAST(:gym_id AS UUID)
