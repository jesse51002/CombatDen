-- Reclaim a 'running' item whose claim is stale — its process died mid-run
-- (every live attempt finishes well under the stale threshold). Counts as a
-- fresh attempt.
UPDATE task_items
SET status = 'running',
    attempt_count = attempt_count + 1,
    started_at = now()
WHERE task_item_id = :task_item_id
  AND status = 'running'
  AND started_at < now() - make_interval(secs => :stale_seconds)
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
    proration_behavior::text AS proration_behavior,
    created_at,
    started_at,
    finished_at
