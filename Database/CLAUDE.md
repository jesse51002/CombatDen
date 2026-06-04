# Supabase Project

## No assumptions

When a decision has more than one reasonable answer, ask and wait for the user's explicit response. Never assume, recommend-and-proceed, or defer the choice unilaterally. Presenting researched options is encouraged; making the choice for the user is not.

## Skills are living documents

When working through a skill (or a reference doc / `SKILL.md` it loads) you realize its guidance is wrong, outdated, or holding the work back — a recommended data/image source that returns bad results, a step that no longer fits, a better tool you've found — do not silently work around it. Use the better approach for the task, then **recommend the specific skill fix to the user and wait for approval** (per *No assumptions*); on approval, **update the skill file** so the lesson sticks. Skills are ever-evolving — every real-world correction should feed back into them.

## CLAUDE.md is a living document

This file is a living document — exactly like a skill, it must track reality. Whenever the schema, access rules, Python models, or workflow genuinely diverge from what this CLAUDE.md says (a new table/enum, a renamed file, a changed convention), **update this file in the same change** so the doc and the code never drift apart. Never leave it stale: a stale rule produces false "violation" findings in review and misleads the next contributor. If a documented rule is what diverged, fix the doc to match the new reality; if the divergence is a mistake, fix the code. Either way, doc and code must agree when you are done.

## Schema workflow
- **Never edit migration files directly.** Only modify schema files in `schemas/` and access rules in `access_rules/`.
- The user will run the Supabase migration command themselves.
- **Never run the migration script** (`supabase db reset`, `supabase migration`, etc.) — the user always runs migrations manually because they need to reset the data. **Do not execute these commands under any circumstances.**
- **Never run the seeding script** (`python python_data/main.py`, etc.) — the user will seed data manually. **Do not execute these commands under any circumstances.**

## Security
- Always enable Row Level Security (RLS) on every table.
- Always use `REVOKE UPDATE` on immutable columns (e.g. PKs, FKs, created_at) for the `authenticated` role.
- **Stripe-gated tables are `service_role`-WRITE-ONLY.** Any table with a `stripe_*_id` column — the billing tables (`member_charges`, `member_invoices`, `member_invoice_line_items`, `member_invoice_applied_discounts`, `member_membership_applied_discounts`), `membership_plans`, `membership_plan_prices`, `member_memberships`, `stripe_webhook_events` — must NOT have INSERT or UPDATE RLS policies for the `authenticated` role. Those operations go through `service_role` only. SELECT policies for `authenticated` are allowed, but must use the `hide_incomplete_stripe_records` restrictive-SELECT pattern (filter out rows where the Stripe ID is NULL or the record is in an incomplete state) so partially-synced data is never surfaced to clients.
- **`gym_discounts` is NOT Stripe-gated** (anymore). Discount presets are coupon-free: a coupon is computed at sync-time and written back onto the applied-discount snapshot, not pre-baked on the preset. So `gym_discounts_unfiltered` carries no `stripe_*` column and is plain gym config — gated like `gym_classes`/`gym_rewards` (gym-staff SELECT plus gym-scoped INSERT/UPDATE/DELETE, identity columns immutable), with NO `hide_incomplete_stripe_records` policy and NO service-role-write-only posture. Its `gym_discounts` view is a plain passthrough (no Stripe filter). `member_membership_applied_discounts` is the Stripe-gated half of the discount system (it holds the written-back `stripe_coupon_id`).
- **Exception — `members` (per-column gating).** The unified `members` table mixes client-writable identity (name, email, points, rank — created/edited by gym staff with no Stripe) with `service_role`-only billing columns (`stripe_*`, `card_*`, `freeze_*`, `account_linked_to_id`, `total_monthly_recurring_price`). It is therefore gated **per-column, not per-table**: `authenticated` keeps INSERT/UPDATE on identity columns, but the billing columns are `REVOKE`d (see `access_rules/members.sql`). (`members.linked_discount_id` is gone — linked discounts dissolved into snapshot rows on `member_membership_applied_discounts`; `account_linked_to_id`, the family-billing link, stays.) `members` is deliberately NOT filtered by a `hide_incomplete_stripe_records` policy — engagement-only members have NULL billing columns and must stay visible. Stripe-complete billing reads go through the `member_billing_profile` VIEW (`SELECT * FROM members WHERE stripe_customer_id IS NOT NULL`), which replaced the former separate `member_billing_profile` table when identity + billing were unified onto `members`.
- Append-only tables (logs / history / metrics — `member_attendance`, `class_history`, `gym_history`, `member_activities`, `member_reward_redemptions`) should `REVOKE UPDATE` for `authenticated`.
- **Every view MUST be declared `WITH (security_invoker = true)`.** Without this flag, the view runs with the privileges of its creator (typically `postgres`), which silently bypasses the RLS on the underlying tables and leaks rows across tenants.
- **All access rules go in `access_rules/`, not in `schemas/`.** This includes `ALTER TABLE ... ENABLE ROW LEVEL SECURITY`, `CREATE POLICY`, `REVOKE`, and `GRANT` statements. Each schema file in `schemas/` has a corresponding file in `access_rules/` with the same name. This separation exists to avoid circular dependencies (e.g. RLS policies that reference tables loaded later).

## Integrity constraints
- Always name constraints with the `CONSTRAINT` keyword for readable error messages (e.g. `CONSTRAINT membership_must_match_gym`).
- Always add both an inline foreign key on the column definition AND a composite foreign key at the table level when cross-table gym validation is needed (e.g. `class_id UUID NOT NULL CONSTRAINT fk_schedule_class_id REFERENCES gym_classes(class_id)` inline, plus `CONSTRAINT fk_schedule_class FOREIGN KEY (class_id, gym_id) REFERENCES gym_classes (class_id, gym_id)` at the bottom).
- Prefer composite foreign keys over triggers for cross-table validation (e.g. ensuring member_id belongs to the correct gym_id).
- Only use triggers when the constraint can't be expressed as a FK (e.g. JSONB array validation, immutability logic).
- Keep triggers in the same schema file as the table they apply to, not in a separate file.

## Naming
- Tables that belong to a single owning entity get the entity's name as a prefix, even at the cost of slightly longer names. Examples: `member_attendance`, `member_activities`, `member_reward_redemptions`, `member_memberships`, `class_history`, `class_instance_exceptions`, `class_range_exceptions`, `gym_classes`, `gym_ranks`, `gym_rewards`, `gym_history`. The prefix groups related tables together in directory listings, in dbdiagram, and in the Supabase Studio sidebar — and disambiguates names that would otherwise collide across owning entities (e.g. there could be `class_history` and `member_activities`, never just `history` or `activities`).
- Mirror the prefix in the file name, the table name, the constraint name (`fk_<table>_<purpose>`), the index name (`idx_<table>_<purpose>`), and the matching Python schema/generator/bootstrap module. Drift between any of these makes search painful.

## Enums
- Always use real Postgres enums (`CREATE TYPE foo AS ENUM (...)`) for any column with a fixed set of string values. Never use `CHECK (col IN ('a','b','c'))` for that case — the enum surfaces in PostgREST's OpenAPI output, in Supabase Studio dropdowns, and gives clearer errors than a CHECK violation.
- Declare the `CREATE TYPE` at the top of the schema file that owns the consuming table. If multiple tables consume the same enum, hoist into the earliest-loaded file that uses it.
- Mirror every Postgres enum with a `StrEnum` in `python_data/schema/*.py` whose member values are character-identical to the Postgres values, so the seed and the DB round-trip cleanly.

## Immutable Columns

`python_data/schema/immutable_columns.py` defines frozensets of column names per table that must never appear in an UPDATE SET clause from **user-facing update requests** (i.e. data sent by the client). These are not about what the backend/service_role can write — they guard against clients modifying columns they shouldn't (PKs, FKs, auto-generated timestamps, Stripe-managed columns, backend-managed columns like linking and discount assignments, etc.).

- **Always keep this file in sync with schema changes** — when adding, removing, or renaming columns in `schemas/`, update `immutable_columns.py` to match.
- The FastAPI backend imports these via `from schema.immutable_columns import <TABLE_NAME>` (available through `db_schema_path.py`).
- Used with `validate_mutable_columns()` in `src/shared/column_guard.py` to reject update requests that try to write immutable columns.

## Structure
- `schemas/` — source-of-truth SQL for each table (DDL, constraints, indexes, triggers)
- `access_rules/` — RLS policies, REVOKE/GRANT statements for each table (loaded after all schemas to avoid circular dependencies)
- `migrations/` — generated migration files (do not touch)
- `python_data/schema/` — shared Python enums, Pydantic models, and immutable column definitions used by both the seeding scripts and the FastAPI backend
- `schema_db_diagram.io` — dbdiagram.io markup; always update this file when adding, removing, or renaming columns/tables
- `config.toml` — Supabase project config
