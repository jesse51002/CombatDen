-- Hand-authored migration.
-- Adds gyms.created_at — the gym's row-creation timestamp, mirroring
-- members.created_at. Backs the reports/exports month-picker floor (a
-- gym's earliest selectable report month). Mirrors schemas/gyms.sql.
--
-- Added as NOT NULL DEFAULT now(): now() is STABLE (not VOLATILE), so
-- Postgres 11+'s fast-default optimization applies — this is a
-- metadata-only change, no table rewrite, no separate backfill step.
-- Every pre-existing gym reads back with the timestamp of this ALTER
-- (its literal creation time isn't recoverable), which is fine for a
-- picker floor. Small, additive: no data loss.

ALTER TABLE gyms
    ADD COLUMN created_at TIMESTAMPTZ NOT NULL DEFAULT now();

-- Identity columns stay immutable; mirrors access_rules/gyms.sql.
REVOKE UPDATE (created_at) ON TABLE gyms FROM authenticated;
