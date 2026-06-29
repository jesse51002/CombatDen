# Supabase Project

## No assumptions

When a decision has more than one reasonable answer, ask and wait for the user's explicit response. Never assume, recommend-and-proceed, or defer the choice unilaterally. Presenting researched options is encouraged; making the choice for the user is not.

## CLAUDE.md is a living document

This file is a living document — exactly like a skill, it must track reality. Whenever the schema, access rules, Python models, or workflow genuinely diverge from what this CLAUDE.md says (a new table/enum, a renamed file, a changed convention), **update this file in the same change** so the doc and the code never drift apart. Never leave it stale: a stale rule produces false "violation" findings in review and misleads the next contributor. If a documented rule is what diverged, fix the doc to match the new reality; if the divergence is a mistake, fix the code. Either way, doc and code must agree when you are done.

## Schema workflow
- **Modify the schema files in `schemas/` and access rules in `access_rules/` first** — they are the source of truth for the desired end state.
- **Hand-write every migration. NEVER auto-generate one (`supabase db diff`).** Auto-generated migrations have repeatedly caused problems here — they strip `security_invoker` off recreated views (a tenant-leak RLS bypass), drop/recreate objects destructively, order statements badly, and silently miss things Postgres can't diff (enum-value retirements need a hand-written type-recreate). The migration is authored by hand to match the schema-file changes, never machine-diffed.
- **Delegate migration authoring to a sub-agent.** When a schema change needs a migration, spin up a sub-agent whose sole job is to hand-write it: read the changed `schemas/` / `access_rules/` files (the end state) **and the latest existing migration** (the base it builds on), then write a clean, correctly-ordered migration that reaches the schema-file end state — preserving `security_invoker` on every recreated view, handling enum changes via a type-recreate, and dropping dependent views before altering their tables. The sub-agent must **not run any migration/seed command**. **Sonnet is fine for this**; always review the sub-agent's migration before finishing.
- The user will run the Supabase migration command themselves.
- **Never run the migration script** (`supabase db reset`, `supabase migration`, etc.) — the user always runs migrations manually because they need to reset the data. **Do not execute these commands under any circumstances.**
- **Never run the seeding script** (`python python_data/main.py`, etc.) — the user will seed data manually. **Do not execute these commands under any circumstances.**

## Security
- Always enable Row Level Security (RLS) on every table.
- Always use `REVOKE UPDATE` on immutable columns (e.g. PKs, FKs, created_at) for the `authenticated` role.
- **Stripe-gated tables are `service_role`-WRITE-ONLY.** Any table with a `stripe_*_id` column — the billing tables (`member_charges`, `member_invoices`, `member_invoice_line_items`, `member_invoice_applied_discounts`, `member_membership_applied_discounts`), `membership_plans`, `membership_plan_prices`, `member_memberships`, `stripe_webhook_events` — must NOT have INSERT or UPDATE RLS policies for the `authenticated` role. Those operations go through `service_role` only. SELECT policies for `authenticated` are allowed, but **whether a table needs the `hide_incomplete_stripe_records` restrictive-SELECT pattern depends on how the row reaches it** — do NOT apply it blanket:
  - **DB-first synced tables** (`member_memberships`, `member_membership_applied_discounts`, `membership_plans`, `membership_plan_prices`): the backend writes the row to Postgres *first*, then pushes it to Stripe and back-fills the `stripe_*_id`. That leaves a real transient window where the row exists but isn't on Stripe yet (`stripe_item_id IS NULL`, or `stripe_sync_status IN ('not_added','preview_add','preview_remove')`). These **MUST** carry `hide_incomplete_stripe_records` so pre-sync / preview-staged rows never surface to clients (pattern in `access_rules/member_memberships.sql`).
  - **Terminal event-record tables** (`member_charges`, `member_invoices`, `member_invoice_line_items`, `member_invoice_applied_discounts`): each row is written **once, after the fact** — either from a completed Stripe webhook (the `stripe_*_id` is already in the event payload) or from a completed cash transaction (no Stripe id *by design* — see `member_invoices.stripe_invoice_id` "nullable for cash" and the `payment_has_charge_id` CHECK that allows `payment_method_type='cash'`). There is no partially-synced state to hide, so these tables **do NOT** use `hide_incomplete_stripe_records` — a `stripe_*_id IS NOT NULL` filter would wrongly suppress legitimate **cash** invoices/charges from members and staff.
  - `stripe_webhook_events` is an insert-only event log with no client SELECT path at all.
- **`gym_discounts` + `gym_discount_values` are NOT Stripe-gated.** The discount system is **three tables**: `gym_discounts` (IDENTITY — name + `discount_type` ∈ preset|custom), `gym_discount_values` (versioned, **immutable** VALUE rows — percent/dollar + lifetime spec; editing a value mints a NEW active version and deactivates the old one, mirroring `membership_plan_prices`'s `is_active` + the ≤1-active partial unique index — a permanent paper trail), and `member_membership_applied_discounts` (slim snapshots that reference an immutable `value_id`, freezing a member's discount to that exact version). Coupons are computed at sync and written back onto the applied snapshot, so **neither the identity nor the value rows carry a `stripe_*` column**. `gym_discounts` (identity) is plain gym config gated like `gym_classes`/`gym_rewards` (gym-staff SELECT + gym-scoped INSERT/UPDATE/DELETE). `gym_discount_values` is **truly immutable + service_role-write-only, exactly like `membership_plan_prices`** — authenticated gets SELECT only; the backend (service_role) inserts a new version and flips the prior `is_active`; the value columns are never mutated and versions are never deleted (a permanent paper trail referenced by applied snapshots). Their views are plain passthroughs (no Stripe filter, since neither carries a `stripe_*` column). `member_membership_applied_discounts` is the **Stripe-gated half** (it holds the written-back `stripe_coupon_id`): unfiltered base + filtered view + `hide_incomplete_stripe_records`.
- **Exception — `members` (per-column gating).** The unified `members` table mixes client-writable identity (name, email, points, rank — created/edited by gym staff with no Stripe) with `service_role`-only billing columns (`stripe_*`, `card_*`, `freeze_*`, `total_monthly_recurring_price`). It is therefore gated **per-column, not per-table**: `authenticated` keeps INSERT/UPDATE on identity columns, but the billing columns are `REVOKE`d (see `access_rules/members.sql`). (`members.account_linked_to_id` is gone — the single-parent family link was replaced by the `member_authorized_payers` junction, the **authorization** layer: who is *allowed* to pay for whom, not the billing key. Billing is per-payer via `member_memberships.paid_by_member_id` (the resolved payer, or a self-paying member). The old `linked_account_no_stripe` CHECK that forced a linked member to hold no billing state is **dropped** — a member paid for by an authorized payer legitimately holds their own `stripe_sub_id_month` / card / freeze window.) `members` is deliberately NOT filtered by a `hide_incomplete_stripe_records` policy — engagement-only members have NULL billing columns and must stay visible. Stripe-complete billing reads go through the `member_billing_profile` VIEW (`SELECT * FROM members WHERE stripe_customer_id IS NOT NULL`), which replaced the former separate `member_billing_profile` table when identity + billing were unified onto `members`.
- Append-only tables (logs / history / metrics — `member_attendance`, `class_history`, `gym_history`, `member_activities`, `member_reward_redemptions`) should `REVOKE UPDATE` for `authenticated`.
- **`resource_locks` is service-role-only infrastructure** — a generic per-key TTL-lease concurrency lock (the backend's payment-sync engine guards on the paying-parent key). No `stripe_*` column, no client path: like `stripe_webhook_events` it just enables RLS + `REVOKE ALL … FROM authenticated` (no policies, no `_unfiltered` view, not seeded). See `FastApiBackend/src/shared/resource_lock.py`.
- **`tasks` + `task_items` are backend-executed records with staff READ access** — tracked background operations (`task_type` discriminates; `membership_reprice` first): an op endpoint creates the rows and returns the task_id; the CRM polls. Written by the backend at `service_role` only (`REVOKE INSERT, UPDATE, DELETE … FROM authenticated`), gym staff get SELECT via `is_gym_admin_or_owner` so the CRM can show progress and badge in-task memberships. No `stripe_*` column, no `_unfiltered`/view split, not seeded. See `FastApiBackend/src/tasks/`.
- **Waiver tables.** `gym_waivers` is plain gym config (no Stripe) — gated like `gym_classes`/`gym_rewards` (gym-staff SELECT plus gym-scoped INSERT/UPDATE/DELETE, identity columns immutable, no `_unfiltered` view), soft-deleted via `is_deleted`. Its `current_version_id` is a forward FK to `gym_waiver_versions` declared via `ALTER TABLE` at the bottom of the versions schema file (circular ref; the catalog row + first version + current-version pointer are written in one backend transaction). `gym_waiver_versions` is **conditionally immutable** + `REVOKE UPDATE, DELETE` for `authenticated` (clients never write version rows). The backend (service_role) edits the current version **in place while it has 0 signatures**; once a member has signed it, that version is frozen and a body edit **publishes a NEW version row** + re-points `current_version_id`, so a signature bound to a version always reproduces the exact wording (`src/waivers/service/waivers/waivers_update.py::_maybe_publish_version`). `member_waiver_signatures` is an append-only e-sign audit record + **generic signature log** (who signed which waiver version, when, with the audit fields; `REVOKE UPDATE, DELETE`); members see their own, staff see their gym's, and **gym staff record signatures via its INSERT policy** (front-desk clickwrap). A gym's **default authorized-payer waiver** is a `gym_waivers` row flagged `is_default` — protected from client tampering (`trg_prevent_default_waiver_removal` blocks archiving/deleting it for `authenticated`/`anon` roles, `idx_gym_waivers_one_default` enforces ≤1 per gym, and `is_default` is service_role-set at seed/create + REVOKE'd from clients) yet editable like any waiver, seeded as a copy of the platform default. The backend (service_role) **may hard-delete** the default waiver during gym-create teardown (`GymsCreateService._cleanup_pending`): the waiver is seeded before the Stripe account is created, so if the Stripe create fails the cleanup must remove the waiver row to leave no dangling rows. `is_default` immutability is still enforced for ALL roles.
- **`member_authorized_payers`.** The **many-to-many authorization layer** — a row `(member_id, payer_member_id)` says payer X may pay for member Y, gated by a signed waiver (`signature_id` → `member_waiver_signatures`, the proof). Not Stripe-gated; backend-managed (service_role INSERT/DELETE, `authenticated` REVOKE'd; SELECT for gym staff + the two involved members). It is the **authorization** layer only — billing stays per-membership via `member_memberships.paid_by_member_id`. It **replaces** the old single-parent family link (the former `members.account_linked_to_id`, now dropped).
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

## Real-gym video content schema (`gym_video_*`)

The `gym_video_*` tables hold real customer gym video content (UUID-keyed by `gyms.gym_id`), separate
from the `video_gym*` template tables (text-keyed demo content).

**`gym_video_spec` is append-only and versioned.** Every change appends a new row; existing rows are
never UPDATE'd. The `spec_id uuid` is the PK; `gym_id` is NOT unique. Columns:

| Column | Type | Notes |
|---|---|---|
| `spec_id` | `uuid` PK | Immutable row identity |
| `gym_id` | `uuid` | FK to `gyms`; multiple rows per gym (one per version) |
| `videos_desc` | `text` | Full keep-spec (markdown) |
| `avoid_desc` | `text` | Full avoid-spec (markdown) |
| `short_videos_desc` | `text` | Optional short summary |
| `short_avoid_desc` | `text` | Optional short summary |
| `queries` | `jsonb` | Array of search query strings (was a separate table — see below) |
| `source` | `gym_video_spec_source` | Enum: `admin_update` \| `system_update` \| `feed_update` |
| `created_at` | `timestamptz` | Version timestamp |

Three writers, each stamping a distinct `source`:
- `FastApiBackend/src/videos/service/video_agent/` agent / owner save → `admin_update`
- `FastApiBackend/src/presets/` template import → `system_update`
- `FastApiBackend/src/videos/service/` feed refiner (`VideoFeedRefiner`) → `feed_update`

**Read paths use the `gym_video_spec_latest` view**, which surfaces the single most-recent version row
per gym. Never query the underlying `gym_video_spec` table directly in a read path.

**`gym_video_query` was dropped.** Search queries were previously a separate `gym_video_query` table
(one row per query per gym). They are now stored in `gym_video_spec.queries JSONB` as part of the
versioned spec. Do not reference or recreate `gym_video_query`.

**`gym_video_feed` curation audit** — `gym_video_feed` carries a unified curation pair:
- `curation_type gym_video_curation_type NOT NULL DEFAULT 'automatic'` — how the row's CURRENT
  `scan_status` was set: `'manual'` = owner rejected / kept / re-added via the UI;
  `'automatic'` = the scan/import batch placed it. Written by every feed-write path
  (`videos_keep_feed_video.sql`, `videos_reject_feed_video.sql`, `videos_insert_feed_video.sql`,
  `presets_insert_feed.sql`, `presets_insert_rejected_feed.sql`).
- `curation_reason TEXT` — the owner's latest free-text reason for a manual curation. `scan_status`
  already tells keep vs reject, so one field covers both directions. NULL for automatic rows and
  manual actions with no stated reason.
- `curated_at` — when the owner last manually touched the row (reject/keep/re-add); NULL for
  automatic-only rows. The feed-learning refiner filters on `curation_type = 'manual'` AND
  `curated_at >` the gym's last `feed_update` version to find unconsumed signals.

**`gym_video_spec_source` enum** — a new Postgres enum (`CREATE TYPE gym_video_spec_source AS ENUM
('admin_update', 'system_update', 'feed_update')`), mirrored in
`python_data/schema/` as a Python `StrEnum`. Update `immutable_columns.py` if `spec_id` or `source`
are columns that must be guarded (they are immutable once written).

## Structure
- `schemas/` — source-of-truth SQL for each table (DDL, constraints, indexes, triggers)
- `access_rules/` — RLS policies, REVOKE/GRANT statements for each table (loaded after all schemas to avoid circular dependencies)
- `migrations/` — generated migration files (do not touch)
- `python_data/schema/` — shared Python enums, Pydantic models, and immutable column definitions used by both the seeding scripts and the FastAPI backend
- `schema_db_diagram.io` — dbdiagram.io markup; always update this file when adding, removing, or renaming columns/tables
- `seed.mermaid` — Mermaid map of the end-state spread of everything `make seed` (`python_data/main.py`) creates (counts, types, proportions per gym); a living doc — keep it in sync with `constants.py` and the `python_data/` generators whenever the seed's outputs change. Author/edit it with the `mermaid-creation` skill (top-down `TB`, sibling-only edges, render + `check_siblings.py` + Mermaid-9 parse).
- `config.toml` — Supabase project config
