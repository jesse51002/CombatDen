-- HAND-AUTHORED migration (not `supabase db diff` output).
--
-- Adds the per-gym white-label member-app store listings to `gyms`, feeding
-- the public app-download page in Kiosk Mode's app-adoption funnel.
--
-- Both columns are nullable TEXT. NULL = the gym has not set its own listing,
-- so the public GET /api/v1/gyms/{gym_id}/app-links endpoint falls back to the
-- CombatDen default listing (Settings). They are client-editable (white-label),
-- so neither is added to the immutable GYMS frozenset, and no access-rule
-- change is needed: the client roles hold NO privileges on any table
-- (20260721151119_revoke_client_data_surface.sql), and the backend reads them
-- via the service_role direct pool.
--
-- Additive, nullable, no backfill, no view/enum/trigger touched.

ALTER TABLE gyms
    ADD COLUMN app_store_url TEXT,
    ADD COLUMN play_store_url TEXT;
