SELECT g.gym_id, g.gym_name, g.gym_description, g.timezone
FROM gyms g
JOIN gym_employees ge ON ge.gym_id = g.gym_id
WHERE ge.user_id = :user_id
ORDER BY ge.created_at ASC
LIMIT 1
