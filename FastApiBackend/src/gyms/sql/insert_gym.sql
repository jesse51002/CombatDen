INSERT INTO gyms (gym_name, gym_description, timezone)
VALUES (:gym_name, :gym_description, :timezone)
RETURNING gym_id, gym_name, gym_description, timezone
