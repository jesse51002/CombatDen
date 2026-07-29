-- Hand-authored migration.
-- Adds gyms.address — the gym's street address, free text exactly as the
-- owner typed it (never parsed into components or geocoded). Nullable with
-- no default: NULL means the gym hasn't set one. Surfaced to members for
-- directions (rendered as text plus an "Open in Maps" link). Mirrors
-- schemas/gyms.sql. Small, additive: no backfill, no table rebuild, no
-- data loss.
--
-- Client-editable, so NO accompanying REVOKE: gym owners edit it in the
-- CRM under the existing "Gym staff can update own gym" policy.

ALTER TABLE gyms
    ADD COLUMN address VARCHAR;
