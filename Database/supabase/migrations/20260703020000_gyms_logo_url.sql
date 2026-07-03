-- Hand-authored migration.
-- Adds gyms.logo_url — the gym's uploaded logo (CDN URL). Nullable with no
-- default: NULL means no logo has been uploaded yet, and clients fall back
-- to a default mark client-side. Mirrors schemas/gyms.sql. Small, additive:
-- no backfill, no table rebuild, no data loss.

ALTER TABLE gyms
    ADD COLUMN logo_url TEXT;
