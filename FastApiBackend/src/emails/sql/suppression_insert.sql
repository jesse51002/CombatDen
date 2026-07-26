-- Idempotent: the two partial unique indexes (gym-scoped and global) make a
-- repeated unsubscribe click a no-op instead of an unbounded pile of rows.
INSERT INTO email_suppressions (gym_id, email, scope, reason)
VALUES (
    CAST(:gym_id AS UUID),
    lower(:email),
    CAST(:scope AS email_suppression_scope),
    :reason
)
ON CONFLICT DO NOTHING
RETURNING suppression_id
