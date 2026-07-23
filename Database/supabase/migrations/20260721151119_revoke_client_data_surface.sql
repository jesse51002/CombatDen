-- HAND-AUTHORED migration (not `supabase db diff` output).
--
-- Closes the client (PostgREST) data surface entirely: `anon` and
-- `authenticated` lose EVERY privilege on EVERY table, view and sequence in
-- `public`, and the default privileges that hand those grants to future
-- objects are revoked too.
--
-- WHY
-- ---
-- Supabase's platform defaults GRANT table-level ALL on `public` to `anon`
-- and `authenticated`. PostgreSQL **cannot subtract a column privilege from
-- a role that holds the table-level privilege**, so every column-list form
-- (`REVOKE UPDATE (col, ...) ON TABLE x FROM authenticated`) in
-- `access_rules/` was completely inert -- verified on the live database:
--   has_column_privilege('authenticated','gym_employees','email','UPDATE')      -> true
--   has_column_privilege('authenticated','gyms','stripe_account_id','UPDATE')   -> true
--   has_column_privilege('authenticated','members','points_balance','UPDATE')   -> true
-- (The whole-table forms with no column list, e.g. on `member_activities`,
-- DO work -- those were never the problem.)
--
-- Concretely that left two live holes: an `admin` could PATCH the owner's
-- `gym_employees` row (email / employee_type) and take the gym over, and --
-- once the `members` UPDATE policy was re-keyed off the live
-- `lower(members.email) = lower(auth.jwt() ->> 'email')` claim -- any member
-- with a login could PATCH their own `points_balance` / `current_rank_id`
-- straight through PostgREST with the public anon key.
--
-- Nothing legitimately uses that surface. The CRM's only Supabase calls are
-- GoTrue auth (signUp / signInWithPassword / signOut / resend /
-- onAuthStateChange / currentUser); MobileApp has no supabase dependency at
-- all; VideoService connects as `postgres` via `database_url`; the FastAPI
-- backend uses the service-role key plus a direct pool; and the seed writes
-- all data with `SUPABASE_SERVICE_ROLE_KEY`. All access goes through the
-- backend.
--
-- SCOPE
-- -----
-- * `service_role` is deliberately UNTOUCHED (backend + seed depend on it).
-- * The `auth` schema is deliberately UNTOUCHED (GoTrue login must keep
--   working -- the anon key is still the `apikey` header on
--   /auth/v1/token, which is auth, not data).
-- * Functions are deliberately UNTOUCHED: the SECURITY DEFINER RLS helpers
--   (`is_gym_employee`, `is_gym_admin_or_owner`, `gym_has_owner`) are
--   evaluated as the querying role, and a client that holds no table
--   privilege never reaches them anyway.
-- * Every RLS policy STAYS IN PLACE, deliberately -- they are now
--   defense-in-depth (a second, independent lock) rather than the only lock.
-- * The 16 inert column-list REVOKEs in `access_rules/` are left as-is:
--   harmless no-ops once the table-level grant is gone.
--
-- Mirrors access_rules/zz_client_privileges.sql (the end-state source of
-- truth), and the removal of the anon/authenticated GRANTs formerly in
-- access_rules/rank_presets.sql and access_rules/members.sql.

-- ============================================================
-- 1. Strip every existing privilege on public from the client roles.
--    ALL TABLES covers views as well (both are relations).
-- ============================================================

REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM anon, authenticated;
REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public FROM anon, authenticated;

-- ============================================================
-- 2. Stop FUTURE objects from silently regaining them.
--    Default privileges are recorded per (grantor role, schema), so both
--    forms are needed: the plain one covers objects created by the role
--    running this migration, the FOR ROLE postgres one covers the entry
--    Supabase's bootstrap installed for `postgres` (the role that owns the
--    schema files' tables).
-- ============================================================

ALTER DEFAULT PRIVILEGES IN SCHEMA public
    REVOKE ALL ON TABLES FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    REVOKE ALL ON SEQUENCES FROM anon, authenticated;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
    REVOKE ALL ON TABLES FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
    REVOKE ALL ON SEQUENCES FROM anon, authenticated;

-- Verify afterwards (read-only, expect `f` for every row):
--   SELECT has_table_privilege('authenticated','members','UPDATE');
--   SELECT has_table_privilege('authenticated','gym_employees','UPDATE');
--   SELECT has_table_privilege('anon','members','SELECT');
--   SELECT has_table_privilege('service_role','members','UPDATE');  -- expect `t`
