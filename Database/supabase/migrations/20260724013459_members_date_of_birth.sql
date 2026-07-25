-- HAND-AUTHORED migration (not `supabase db diff` output).
--
-- Adds `members.date_of_birth` — the optional date of birth the kiosk
-- self-serve signup captures in its optional-details step (and staff can edit
-- from the member page). Mirrors schemas/members.sql + access_rules/members.sql.
--
-- Nullable DATE, no default, no backfill: it sits with the other optional
-- contact columns (phone / address / emergency_contact_*), which are simply
-- NULL for an engagement-only member with nothing on file.
--
-- WHY THIS MIGRATION DROPS AND RECREATES member_billing_profile
-- ------------------------------------------------------------
-- `member_billing_profile` is `SELECT * FROM members WHERE stripe_customer_id
-- IS NOT NULL`. PostgreSQL expands the `*` at CREATE VIEW time and freezes the
-- resulting column list, so a plain ADD COLUMN would leave the view WITHOUT
-- date_of_birth — while a fresh `supabase db reset` (which re-runs
-- schemas/members.sql) WOULD have it. That divergence is exactly what the
-- read path cannot tolerate: `src/members/sql/member_details/member_details.sql`
-- selects the contact block off this view (`mbp.address`, `mbp.phone`, …), so
-- the migrated database would 500 on a column the schema file says exists.
-- Dropping + recreating the view is therefore mandatory, not cosmetic. It is
-- the same step migrations 20260622233350 and 20260711010001 already take for
-- this view.
--
-- No other object depends on the new column: every other view over `members`
-- names its columns explicitly, and DROP VIEW here is safe because nothing
-- depends on member_billing_profile itself (only application queries read it).
--
-- security_invoker is re-declared on the recreated view (twice: inline and via
-- ALTER, matching the schema file's own safety net) — without it the view runs
-- as its creator and silently bypasses `members`' RLS, a cross-tenant leak.

-- ============================================================
-- 1. Drop the SELECT * view so it can pick up the new column.
-- ============================================================

DROP VIEW IF EXISTS member_billing_profile;

-- ============================================================
-- 2. Add the column. Nullable, no default -> metadata-only, no table rewrite.
-- ============================================================

ALTER TABLE members
    ADD COLUMN date_of_birth DATE;

-- ============================================================
-- 3. Recreate member_billing_profile exactly as in schemas/members.sql.
--    DROP VIEW dropped its privileges; they are NOT re-granted to the client
--    roles — `anon` / `authenticated` hold no privileges on any relation in
--    `public` (20260721151119_revoke_client_data_surface.sql +
--    access_rules/zz_client_privileges.sql). The explicit REVOKE below keeps
--    that end state even if a platform default hands the new view a grant.
-- ============================================================

CREATE VIEW member_billing_profile
WITH (security_invoker = true)
AS
SELECT * FROM members WHERE stripe_customer_id IS NOT NULL;

ALTER VIEW member_billing_profile SET (security_invoker = true);

REVOKE ALL PRIVILEGES ON member_billing_profile FROM anon, authenticated;

-- ============================================================
-- 4. Mirror access_rules/members.sql: date_of_birth joins the contact /
--    billing column list revoked from `authenticated`. Inert on its own (a
--    column-list REVOKE cannot subtract from a table-level GRANT, and the
--    client roles hold none anyway) — kept so the migration and the
--    access-rules end state read identically. See Database/CLAUDE.md.
-- ============================================================

REVOKE INSERT, UPDATE (date_of_birth) ON TABLE members FROM authenticated;
