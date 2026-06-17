-- A retryable failure: record the error and release the item back to
-- 'pending' so the next attempt (in-process retry loop or the sweep) can
-- claim it.
UPDATE task_items
SET status = 'pending',
    error_message = :error_message
WHERE task_item_id = :task_item_id
  AND status = 'running'
