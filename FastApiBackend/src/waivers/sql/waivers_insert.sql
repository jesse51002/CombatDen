INSERT INTO gym_waivers (
    gym_id,
    name
) VALUES (
    :gym_id,
    :name
)
RETURNING *
