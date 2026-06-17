-- The in-task guard: which of these membership rows are referenced by an
-- UNFINISHED task item (as the row being acted on, or as the successor a
-- still-running operation produced)? Membership mutations on a referenced row
-- are rejected until the task finishes.
SELECT DISTINCT membership_item_id
FROM (
    SELECT old_item_id AS membership_item_id
    FROM task_items
    WHERE status IN ('pending', 'running')
      AND old_item_id = ANY(CAST(:item_ids AS UUID[]))
    UNION ALL
    SELECT new_item_id
    FROM task_items
    WHERE status IN ('pending', 'running')
      AND new_item_id = ANY(CAST(:item_ids AS UUID[]))
) AS refs
