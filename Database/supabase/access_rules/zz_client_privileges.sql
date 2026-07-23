-- ============================================================
-- Client roles hold NO privileges on public. LOADS LAST.
--
-- This is the one access_rules file with no matching schemas/ file: it is a
-- schema-wide rule, not a per-table one, so it is named `zz_...` to sort
-- last inside the `./access_rules/*.sql` glob in config.toml (the CLI
-- expands a glob in sorted order and de-dupes against already-listed paths,
-- so alphabetical position is what orders it). Load order is belt-and-braces
-- only -- no other access_rules file grants anything to anon/authenticated,
-- so there is nothing left for a later file to re-open.
--
-- WHY THIS EXISTS
-- ---------------
-- Supabase's platform defaults GRANT table-level ALL on `public` to `anon`
-- and `authenticated`. PostgreSQL cannot subtract a COLUMN privilege from a
-- role that holds the TABLE-level privilege, so every column-list
-- `REVOKE UPDATE (col, ...) ... FROM authenticated` elsewhere in this
-- directory was inert (verified on the live DB:
-- `has_column_privilege('authenticated','members','points_balance','UPDATE')`
-- was `true`). That let any member with a login PATCH their own points/rank,
-- and any admin PATCH the owner's employee row, straight through PostgREST
-- with the public anon key.
--
-- Nothing legitimately reads or writes data as anon/authenticated: the CRM
-- uses Supabase only for GoTrue auth, MobileApp has no supabase dependency,
-- VideoService connects as `postgres`, and the FastAPI backend + seed use
-- the service role. ALL data access goes through the backend.
--
-- INVARIANTS
-- ----------
-- * NEVER add a `GRANT ... TO anon` or `GRANT ... TO authenticated` anywhere
--   in access_rules/ -- it would re-open the surface this file closes.
-- * `service_role` is untouched (backend + seed).
-- * The `auth` schema is untouched (GoTrue login).
-- * Functions are untouched: the SECURITY DEFINER RLS helpers are evaluated
--   as the querying role, and a client holding no table privilege never gets
--   that far.
-- * Every RLS policy in this directory STAYS -- with the grants gone they are
--   deliberate defense-in-depth, a second independent lock, not dead code.
-- * If some column ever genuinely needs client writes, the working pattern is
--   REVOKE the whole table then GRANT the allowed columns back:
--     REVOKE UPDATE ON TABLE x FROM authenticated;
--     GRANT UPDATE (allowed_col) ON TABLE x TO authenticated;
--   -- never a column-list REVOKE on top of a table-level GRANT.
-- ============================================================

REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM anon, authenticated;
REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public FROM anon, authenticated;

-- Future objects must not silently regain them. Default privileges are
-- recorded per (grantor role, schema), hence both forms.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    REVOKE ALL ON TABLES FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    REVOKE ALL ON SEQUENCES FROM anon, authenticated;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
    REVOKE ALL ON TABLES FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
    REVOKE ALL ON SEQUENCES FROM anon, authenticated;
