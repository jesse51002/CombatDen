-- Extend our lease on :lock_key only while we still hold it (token matches).
-- RETURNING yields the token when the heartbeat landed; 0 rows means the row is
-- gone or another operation re-took the lease after ours expired, so the caller
-- must treat the lock as lost. CAST(...) (never ::) per the asyncpg text() bind
-- rule.
UPDATE resource_locks
   SET expires_at = now() + (:ttl_seconds * interval '1 second')
 WHERE lock_key = :lock_key
   AND token = CAST(:token AS UUID)
RETURNING token;
