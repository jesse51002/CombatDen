-- Atomically take the lock for :lock_key if it is free or its lease has expired.
-- RETURNING yields the token only when we acquired it; 0 rows means a live lease
-- is held by another operation. CAST(...) (never ::) per the asyncpg text() bind
-- rule.
INSERT INTO resource_locks (lock_key, expires_at, token)
VALUES (
    :lock_key,
    now() + (:ttl_seconds * interval '1 second'),
    CAST(:token AS UUID)
)
ON CONFLICT (lock_key) DO UPDATE
   SET acquired_at = now(),
       expires_at  = now() + (:ttl_seconds * interval '1 second'),
       token       = EXCLUDED.token
 WHERE resource_locks.expires_at <= now()
RETURNING token;
