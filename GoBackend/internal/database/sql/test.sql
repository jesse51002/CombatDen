-- name: GetGym :one
SELECT * FROM gyms
WHERE gym_id = $1;
