-- HAND-AUTHORED migration (not `supabase db diff` output).
--
-- Bounds `members.date_of_birth` at the DATABASE layer, matching the CHECK now
-- declared in schemas/members.sql (`date_of_birth_plausible`). Follows
-- 20260724013459_members_date_of_birth.sql, which added the nullable column.
--
-- WHY
-- ---
-- The column arrived bare (`date_of_birth DATE`, no CHECK) and the Pydantic
-- request models typed it as `date | None` with no validator, so the kiosk
-- self-serve signup — which takes a free-form date — could POST `2035-06-01`
-- (a slipped year) or `0202-06-01` (a mistyped one) and get a 201. Every
-- age-derived read downstream then inherits the nonsense, and nothing in the
-- stack ever says no. This migration is the DB half; the API half is
-- `EARLIEST_DATE_OF_BIRTH` + `_validate_date_of_birth` in
-- FastApiBackend/src/members/schema/members_schema.py (a 422 on both the
-- create and the update model). Both layers on purpose: the CHECK is the
-- backstop for every writer that does not pass through those models — the
-- seed, a future importer, a hand-run UPDATE.
--
-- THE BOUNDS
-- ----------
--   upper: CURRENT_DATE — a date of birth that has not happened yet is never
--          valid data.
--   lower: 1900-01-01 — a fixed calendar floor, not a maximum age. The oldest
--          verified human ever lived to 122, so this can never reject a real
--          member, while it does reject the realistic typo class (a truncated
--          or mistyped year). A fixed date needs no per-gym policy and never
--          becomes wrong as time passes.
--
-- NULL stays legal: the column is optional and sits with the other contact
-- columns, which are simply NULL for an engagement-only member.
--
-- WHY A NON-IMMUTABLE `CURRENT_DATE` IS SAFE HERE
-- -----------------------------------------------
-- CURRENT_DATE is STABLE, not IMMUTABLE. That is normally a footgun in a CHECK
-- because a row can silently stop satisfying the constraint later, breaking a
-- restore or a subsequent VALIDATE CONSTRAINT. It cannot happen for THIS
-- predicate: the bound only ever moves FORWARD, so a row that satisfies
-- `date_of_birth <= CURRENT_DATE` today satisfies it for all time. Verified
-- empirically that PostgreSQL accepts it in a CHECK (it does), and
-- `gyms_timezone_valid` in schemas/gyms.sql already sets the precedent for a
-- non-immutable CHECK in this schema.
--
-- EXISTING ROWS
-- -------------
-- A CHECK constraint fails to APPLY if any existing row violates it, so the
-- live local database was queried read-only before writing this migration:
--
--   SELECT count(*) FROM members
--    WHERE date_of_birth IS NOT NULL
--      AND (date_of_birth < DATE '1900-01-01' OR date_of_birth > CURRENT_DATE);
--   -- 0
--
-- 157 members, 1 of them with a date_of_birth on file, 0 violations — so this
-- applies cleanly with no backfill and no NOT VALID staging step. (The seed
-- generates ages 18–65, which are inside the bounds by construction.)
--
-- No view depends on this: a CHECK changes no column list, so
-- `member_billing_profile` (a `SELECT *` view) does NOT need the drop-and-
-- recreate dance that adding the column required. Nothing else to touch —
-- immutable_columns.py already lists date_of_birth's peers correctly and this
-- adds no column.

-- ============================================================
-- 1. Bound the column. Table-level ADD CONSTRAINT: PostgreSQL validates every
--    existing row (0 violations, verified above) and takes a brief
--    ACCESS EXCLUSIVE lock on `members` for the scan. 157 rows — instant.
-- ============================================================

ALTER TABLE members
    ADD CONSTRAINT date_of_birth_plausible
    CHECK (
        date_of_birth IS NULL
        OR (
            date_of_birth >= DATE '1900-01-01'
            AND date_of_birth <= CURRENT_DATE
        )
    );
