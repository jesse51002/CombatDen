-- The gym's saved ThemeService design id for the showcase read. NULL until the
-- gym chooses a theme. A member re-themes the mobile app to their gym's
-- branding from it; every employee role reads it too.
SELECT theme_design_id
FROM gyms
WHERE gym_id = CAST(:gym_id AS UUID)
