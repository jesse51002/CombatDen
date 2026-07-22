UPDATE gyms
SET {set_clause}
WHERE gym_id = :gym_id
RETURNING gym_id, created_at, gym_name, gym_description, timezone, sub_rank_type, logo_url, theme_design_id
