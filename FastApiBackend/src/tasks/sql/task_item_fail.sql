-- Mark a running item failed (terminal, after max attempts). The operation
-- handled its own failure (verify-or-revert), so a failed item is purely a
-- record: the error message + the fact nothing changed.
UPDATE task_items
SET status = 'failed',
    error_message = :error_message,
    finished_at = now()
WHERE task_item_id = :task_item_id
  AND status = 'running'
