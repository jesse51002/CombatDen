-- Create one task ('pending'); its items are inserted in the same transaction
-- (task_items_insert.sql).
INSERT INTO tasks (gym_id, task_type)
VALUES (CAST(:gym_id AS UUID), CAST(:task_type AS task_type))
RETURNING task_id
