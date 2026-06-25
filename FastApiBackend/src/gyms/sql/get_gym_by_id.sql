SELECT gym_id, gym_name, gym_description, timezone, theme_design_id
FROM gyms
WHERE gym_id = :gym_id
