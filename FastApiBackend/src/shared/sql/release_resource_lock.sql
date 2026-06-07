-- Release the lock only if we still hold it (token matches). A no-op when our
-- lease already expired and was re-taken by another operation, so we never delete
-- someone else's lease. CAST(...) (never ::) per the asyncpg text() bind rule.
DELETE FROM resource_locks
 WHERE lock_key = :lock_key
   AND token = CAST(:token AS UUID);
