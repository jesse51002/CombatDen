-- Atomically claim a pending item: exactly one claimer wins (the WHERE gate
-- makes a concurrent second claim return no row). Each claim is one attempt;
-- started_at records when the CURRENT attempt began (stale-claim detection).
UPDATE task_items
SET status = 'running',
    attempt_count = attempt_count + 1,
    started_at = now()
WHERE task_item_id = :task_item_id
  AND status = 'pending'
RETURNING
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
