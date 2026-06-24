DELETE FROM tasks
WHERE NOT EXISTS (
    SELECT 1 FROM task_items ti WHERE ti.task_id = tasks.task_id
)
