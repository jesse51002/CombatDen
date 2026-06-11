-- Mark a running item completed (terminal). Clears the error of any earlier
-- failed attempt — the item ultimately succeeded.
UPDATE task_items
SET status = 'completed',
    error_message = NULL,
    finished_at = now()
WHERE task_item_id = :task_item_id
  AND status = 'running'
