-- Stamp the successor membership row onto the item. Called by the reprice
-- task executor AFTER the reprice op fully converges (the successor is
-- already synced/applied), in the executor's own post-reprice transaction —
-- so new_item_id is only ever set on a completed item, and a not_added
-- successor left by a crashed or failed reprice is never referenced here.
UPDATE task_items
SET new_item_id = CAST(:new_item_id AS UUID)
WHERE task_item_id = :task_item_id
