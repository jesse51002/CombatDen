-- Read every item of the given tasks (oldest first, stable order).
SELECT
    task_item_id,
    task_id,
    gym_id,
    member_id,
    status::text AS status,
    attempt_count,
    error_message,
    old_item_id,
    new_item_id,
    target_price_id,
    prorate,
    created_at,
    started_at,
    finished_at
FROM task_items
WHERE task_id = ANY(CAST(:task_ids AS UUID[]))
ORDER BY created_at, task_item_id
