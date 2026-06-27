-- Stamp the successor membership row onto the item. Executed INSIDE the
-- operation's own DB transaction (the caller provides the session, no commit
-- here) so a non-NULL new_item_id is the durable "DB phase done" marker — a
-- crashed/retried item with new_item_id set skips straight to the convergent
-- sync.
UPDATE task_items
SET new_item_id = CAST(:new_item_id AS UUID)
WHERE task_item_id = :task_item_id
