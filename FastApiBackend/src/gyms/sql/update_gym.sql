UPDATE gyms
SET {set_clause}
WHERE gym_id = :gym_id
RETURNING gym_id, gym_name, gym_description, timezone
