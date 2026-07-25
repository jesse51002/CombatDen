-- The reconciler's retry sweep: unfinished rows, oldest first, under the
-- attempt ceiling. 'held' and 'suppressed' are deliberately absent — both
-- are terminal by policy, and draining held rows must be an explicit act,
-- never a side effect of enabling a kind.
SELECT
    email_id,
    gym_id,
    kind,
    subject_id,
    payload,
    status,
    attempts
FROM email_log
WHERE status IN ('pending', 'failed')
  AND attempts < :max_attempts
ORDER BY created_at
LIMIT :limit
