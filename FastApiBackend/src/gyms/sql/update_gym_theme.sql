-- Save the gym's chosen ThemeService design id (branding).
-- ThemeService remains a separate service; this just stores the
-- selected design's id (see theme_design_id comment in gyms.sql).
UPDATE gyms
SET theme_design_id = :theme_design_id
WHERE gym_id = CAST(:gym_id AS UUID)
RETURNING gym_id, theme_design_id
