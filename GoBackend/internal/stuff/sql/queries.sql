-- name: GetStuff :one
SELECT id, email, name, created_at, updated_at
FROM users
WHERE id = $1;

-- name: GetJustName :one
SELECT name, created_at
FROM users
WHERE id = $1;
