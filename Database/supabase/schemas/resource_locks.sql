-- Generic distributed lock: one TTL-lease row per arbitrary string key.
-- Service-role-only infrastructure (no client path). Acquire takes the row only
-- when it is free or its lease has expired; a per-acquire token fences release.
-- The lease TTL (set by the backend at acquire time) self-heals a crashed/stuck
-- holder. See FastApiBackend/src/shared/resource_lock.py.
CREATE TABLE resource_locks (
    lock_key TEXT NOT NULL,
    acquired_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL,
    token UUID NOT NULL,
    PRIMARY KEY (lock_key)
);
