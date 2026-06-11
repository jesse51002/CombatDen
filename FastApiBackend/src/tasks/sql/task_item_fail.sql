-- Mark a running item failed (terminal, after max attempts). The DB already
-- encodes the operation's desired state — nothing is reverted; the
-- reconciler's push sweep converges any leftover pending membership row.
UPDATE task_items
SET status = 'failed',
    error_message = :error_message,
    finished_at = now()
WHERE task_item_id = :task_item_id
  AND status = 'running'
