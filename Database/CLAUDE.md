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
- Append-only tables (logs / history / metrics — `gym_history`, `member_activities`, `member_reward_redemptions`) `REVOKE UPDATE` for `authenticated` (they keep a gym-scoped authenticated INSERT policy). **`member_attendance` and `gym_class_schedules` go further — they are `service_role`-WRITE-ONLY** (`REVOKE INSERT, UPDATE, DELETE … FROM authenticated`, no authenticated write policy at all, exactly like `class_signups`/`tasks`): every attendance write flows through the gated check-in path (capacity / eligibility / points / billing-attribution), and every schedule-version mint runs inside the backend transaction that also executes the version-change WIPE (sign-up deletion + check-in reversal + points clawback) — a raw client INSERT would bypass exactly that. `gym_class_schedules` rows are additionally write-ONCE (append-only versions; nobody UPDATEs them — the immutable schedule past). Attendance and sign-ups key an occurrence by its ORIGINAL slot (`class_id`, `original_date`, `original_time` — the owning schedule version's pre-exception slot); `member_attendance.occurred_at` is a denormalized effective-start instant for window SQL only. On `member_attendance`, `plan_id`/`item_id` are **nullable and NULL together** (enforced by `chk_attendance_membership_pair`): an admin (non-kiosk) check-in with no covering membership records both NULL (no pack drawn), while a covered check-in sets both. Cycle-count / streak reads ignore the NULL-membership rows. The composite FKs use MATCH SIMPLE, so a NULL-membership row simply skips them.
- **`member_reward_redemptions` carries a backend-written `status` / `resolved_at` lifecycle** (enum `reward_redemption_status`: `pending` / `approved` / `rejected`). The table still `REVOKE UPDATE`s for `authenticated` — clients never mutate rows. The backend writes status transitions (approve / reject, and the `resolved_at` timestamp) as the `postgres` role, bypassing RLS. A reject also refunds the points balance. `requested_at` (when the member requested the redemption) and `resolved_at` (when staff decided it) were originally named `redeemed_at` / `decided_at`; a `CONSTRAINT resolved_matches_status CHECK ((status = 'pending') = (resolved_at IS NULL))` pairs the two, mirroring `members.sql`'s `freeze_dates_must_be_paired`. Migration `20260628100000_reward_redemption_status.sql` backfills existing rows to `approved`; `20260703000000_rewards_label_and_timestamps.sql` renames the columns, backfills `resolved_at` for the already-decided rows the first migration left NULL, and adds the CHECK. `gym_rewards.amount_off` was also collapsed into `price_label` (a single value-label/badge column) in that same migration.
- **`resource_locks` is service-role-only infrastructure** — a generic per-key TTL-lease concurrency lock (the backend's payment-sync engine guards on the paying-parent key). No `stripe_*` column, no client path: like `stripe_webhook_events` it just enables RLS + `REVOKE ALL … FROM authenticated` (no policies, no `_unfiltered` view, not seeded). See `FastApiBackend/src/shared/resource_lock.py`.
- **`tasks` + `task_items` are backend-executed records with staff READ access** — tracked background operations (`task_type` discriminates; `membership_reprice` first): an op endpoint creates the rows and returns the task_id; the CRM polls. Written by the backend at `service_role` only (`REVOKE INSERT, UPDATE, DELETE … FROM authenticated`), gym staff get SELECT via `is_gym_admin_or_owner` so the CRM can show progress and badge in-task memberships. No `stripe_*` column, no `_unfiltered`/view split, not seeded. See `FastApiBackend/src/tasks/`.
- **`class_signups`** — a member's reservation for a class occurrence (NOT attendance; `member_attendance` is still the only attendance record). SELECT mirrors `member_attendance` — a member sees their own sign-ups, gym staff see everything at their gym — and like `tasks`, there is NO authenticated write policy at all (`REVOKE INSERT, UPDATE, DELETE … FROM authenticated`), because both staff AND the member themselves may create/cancel a sign-up, so the API (`verify_can_view_member`) does the authorization instead of a role-scoped RLS policy. `UNIQUE (class_id, member_id, original_date, original_time)` backs the idempotent `ON CONFLICT DO NOTHING` create (a class may occur several times per day — `gym_class_schedules.weekday_slots` — so the full original slot is the key). See `FastApiBackend/src/checkin/service/signup_service.py`.
- **Waiver tables.** `gym_waivers` is plain gym config (no Stripe) — gated like `gym_classes`/`gym_rewards` (gym-staff SELECT plus gym-scoped INSERT/UPDATE/DELETE, identity columns immutable, no `_unfiltered` view), soft-deleted via `is_deleted`. Its `current_version_id` is a forward FK to `gym_waiver_versions` declared via `ALTER TABLE` at the bottom of the versions schema file (circular ref; the catalog row + first version + current-version pointer are written in one backend transaction). `gym_waiver_versions` is **conditionally immutable** + `REVOKE UPDATE, DELETE` for `authenticated` (clients never write version rows). The backend (service_role) edits the current version **in place while it has 0 signatures**; once a member has signed it, that version is frozen and a body edit **publishes a NEW version row** + re-points `current_version_id`, so a signature bound to a version always reproduces the exact wording (`src/waivers/service/waivers_update.py::_maybe_publish_version`). Each version carries **`requires_resign`** (BOOLEAN default true): a forked version flagged true invalidates prior signers for the membership-purchase gate (they must re-sign), while a minor edit published with `requires_resign = false` keeps prior signatures valid — the gate's compliance floor is the highest `version_number` with `requires_resign = true`. A version `body` is a **template** that may hold `{{placeholders}}` (catalog `python_data/schema/waiver_parameters.py`); at sign time `WaiversSignatures.sign_waiver` renders them (auto member/signer/gym/date + caller `waiver_args` like `payee_name`) and freezes the full **`rendered_body`** + its `content_hash` (sha256 of the rendered text) on the signature. `member_waiver_signatures` is an append-only e-sign audit record + **generic signature log** (`REVOKE UPDATE, DELETE`); members see their own, staff see their gym's, **gym staff record signatures via its INSERT policy** (front-desk clickwrap), and the backend (service_role) also records via the standalone signing endpoint + the authorize-payer link flow. Its legal-evidence columns are NOT-NULL: typed `signer_name`, forced-true `consent_acknowledged`, version-pinned `waiver_version_id`, `rendered_body`, `content_hash`, `ip_address` + `user_agent`, **`esign_disclosure_version`** (the ESIGN/UETA disclosure shown), plus the NULLABLE **`operator_employee_id`** composite FK → `gym_employees` (the staff witness). Every `gym_waivers` row carries a **`waiver_type` enum** (`payer_auth` | `custom`, expandable): `custom` = a gym-authored document attachable to membership plans (`membership_plans.waiver_ids` — validated at plan write time to be existing, non-archived, `custom` waivers only); `payer_auth` = the gym's ONE **authorized-payer agreement** (signed only in the authorize-payer link flow, never plan-attachable) — protected from client tampering (`trg_protect_payer_auth_waiver` blocks archiving/deleting it for `authenticated`/`anon` roles, `idx_gym_waivers_one_payer_auth` enforces ≤1 per gym, and `waiver_type` is service_role-set at seed/create + REVOKE'd from clients + immutable for ALL roles) yet editable like any waiver, seeded as a copy of the platform default. Because the backend itself runs at service role, the trigger does NOT protect the API path — `WaiversDelete.delete_waiver` carries its own payer-auth guard, and archiving a `custom` waiver also strips its id from every plan's `waiver_ids` in the same transaction. The backend (service_role) **may hard-delete** the payer-auth waiver during gym-create teardown (`GymsCreateService._cleanup_pending`): the waiver is seeded before the Stripe account is created, so if the Stripe create fails the cleanup must remove the waiver row to leave no dangling rows.
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
from the `template_gym*` template tables (text-keyed demo content).

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

**`gym_video_scan_status` has a third value, `'pending'`** (`CREATE TYPE gym_video_scan_status AS ENUM
('accepted', 'rejected', 'pending')`, declared in `schemas/gym_video_feed.sql`; added via `ALTER TYPE
... ADD VALUE` in migration `20260703000001_video_worker_rag.sql`, appended last so its ordinal matches
runtime). A `'pending'` row is a worker-written candidate that has not yet been enrich+scan processed;
the scan stage flips it to `'accepted'`/`'rejected'`.

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

## Video worker + RAG schema (`cost_log`, `video_rag`, `member_video_recs`)

The VideoService background **worker** (a separate process; see `VideoService/src/worker/`) runs three
DECOUPLED, DB-backed steps every tick — **cleanup**, **finalize**, and ONE drained heavy step
(**scan**, else **enrich**, else **scrape** — the only quota-bound, run-opening step) — that together
regenerate each gym's feed and build the RAG layer the backend serves per-member recs and the
personalized feed ranking from. Two new tables (`video_rag`, `member_video_recs`), the member
video-taste profile columns on `members`, a status lifecycle on `video_run`, and the generic `cost_log`
support it.
**pgvector** is enabled in `schemas/_extensions.sql` (`CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA
extensions`); embedding columns are `vector(3072)` (`gemini-embedding-001`, native 3072), a
**cross-service contract** pinned to `settings.video_embedding_dim` in the backend (a wrong-width vector
raises rather than writes).

**`video.failure_count`** — a per-video hard-error strike counter (`INTEGER NOT NULL DEFAULT 0`,
`CHECK (failure_count >= 0)`, declared in `schemas/video.sql`). The worker bumps it on a step
exception, resets it to 0 on success, and its cleanup step deletes the video at 3 strikes.

- **`video_rag`** — one RAG row per pooled video: `video_id TEXT` **PK** (FK → `video`, `ON DELETE
  CASCADE`), `summary TEXT`, `facets JSONB` (object CHECK), `embedding vector(3072)`, `embedding_model`,
  `created_at`. The worker enrich stage writes it once per un-enriched video; the summary embedding is
  what recs rank against. It carries an **HNSW index built on a `halfvec` cast**
  (`idx_video_rag_embedding` — `hnsw ((embedding::halfvec(3072)) halfvec_cosine_ops)`; pgvector's HNSW
  caps the `vector` type at 2000 dims, so 3072 is indexed at half precision, recall ~unchanged):
  the ~18.9k unique template videos are enriched up front (the VideoService `enrich-templates` sidecar seeds
  `video_rag` on every `make sync-gyms`), so the table crosses the ~10k exact-scan threshold from the first
  sync and every feed / rec / funnel cosine query needs the ANN index.
- **Member video-taste profile on `members`** — the per-member RAG profile is columns on the `members`
  table, not a sidecar: `video_profile_summary TEXT`, `video_profile_embedding vector(3072)`,
  `video_profile_embedding_model TEXT`, `video_profile_built_at TIMESTAMPTZ` — all nullable, NULL until
  first built. One summary + one embedding per member, lazily (re)built by the backend (service_role)
  from deterministic v1 template text and rebuilt when stale (`video_profile_built_at`). Same model +
  dimension contract as `video_rag.embedding` (compared by cosine). Client-immutable (listed in the
  `MEMBERS` frozenset alongside the Stripe columns).
- **`member_video_recs`** — per-member rec history (the freshness partition), an **append-only event
  log**: one row per serve — `rec_id UUID` PK, `(member_id, gym_id, video_id, category)`,
  `recommended_at`, plus `clicked_at TIMESTAMPTZ` (nullable click signal — NULL = served but not clicked;
  set by the backend when the member opens the rec). There is no stored score, no stored counters, and
  **no already-served anti-join** — ranking is computed entirely at READ time by the unified feed query:
  cosine distance to the member's taste embedding, nudged by a σ-scaled **decayed watch penalty** —
  `SUM(power(0.5, age_seconds / half_life_seconds))` over this member's prior serves of a candidate video
  (a just-served video's penalty is near its full σ-scaled weight, decaying toward 0 as the serve ages,
  half-life `video_watch_penalty_half_life_days` = 7d) — so a served video is nudged back immediately
  after and drifts forward again over the following week, rather than being hard-excluded. A re-serve
  INSERTs another row (no UPDATE, no UNIQUE); "times recommended" = `COUNT(*)` and "last recommended" =
  `MAX(recommended_at)`, both derived by aggregate. Index `(member_id, video_id)` backs that per-video
  decayed-penalty aggregate ("already recommended" weighting is global per member, not per category). No
  vector column. Recs are grouped by the video's genre **`category`** — the column is typed as the
  existing **`video_genre`** enum (the type of `video.tag`, created in the baseline `schemas/video.sql`);
  there is no separate mood-bucket abstraction, so this table declares no new enum.

**No worker queue table, and step-selection is not a per-gym pipeline.** Only the **scrape** step (the
sole per-gym, quota-bound, run-opening step) ever selects a gym; it *derives* the due gym from
timestamps already in these tables (`VideoService/src/worker/sql/worker_select_due_gym.sql`): a gym is
DUE when its latest `gym_video_spec` **`admin_update`** version (tier 1), its latest **manual**
`gym_video_feed.curated_at` settled ≥ 1h ago (tier 2), or its last run ≥ 7 days ago (tier 3) is newer
than its last `video_run`, excluding any gym with a `running` run. Tier-sorted, one gym drained per
scrape pass, under a per-gym **2 / 24h** and system-wide **5 / 24h** rolling run cap (both counting runs
of any status — the poison-loop guard, since a failed run still advances the last-run watermark). A
committed spec change no longer enqueues anything; the scrape step notices the new `admin_update`
version whenever it next runs. The **enrich** and **scan** steps never select a gym at all — they are
global, gym-agnostic sweeps that drain whatever the DB shows as their target set (an un-enriched video;
a `pending` feed row) across every gym in one pass.

**`video_run` gains a status lifecycle.** New `CREATE TYPE video_run_status AS ENUM
('running','completed','failed')`; `status` (DEFAULT `'completed'` so every pre-existing run and the
plain preset-import `INSERT` stays served), `finished_at`, `error` (`'no feed rows'` when a `running` run
still has zero feed rows after a 1h grace window, or `'run ttl exceeded'` when a run never reaches the
completion fraction within 24h). A run is left `running` — a legitimate long-lived multi-tick state, full
of `pending` rows the enrich/scan sweeps are still working through — until the worker's **finalize** step
(every tick, cheap) decides it's done: a `running` run whose terminal (`accepted`/`rejected`) fraction of
ALL its feed rows reaches `worker_run_complete_fraction` (0.9) is completed; otherwise it fails as above.
There is **no orphan rule** — every step is DB-derived and idempotent, so a crashed worker simply leaves
work for the next tick to resume; only the finalize step's zero-row/TTL guards catch a pathologically
stuck run. **Serve invariant:** every "latest run" read is the newest by `created_at` **AND
`status = 'completed'`** (a mid-flight `running` run must never become latest and blank the gym's feed)
**AND** the served row is **enriched AND accepted** — the feed/rec read `INNER JOIN`s `video_rag` so an
accepted row with no embedding stays invisible until the enrich sweep reaches it.

**Generic `cost_log` (replaces `video_cost_log`).** A source-agnostic append-only spend ledger:
`entry_id` PK, `source cost_source` (enum, only `'video'` today — extensible), `run_id TEXT` (the source
table's run — `video_run.run_id` for video spend; NULL outside a run), `gym_id UUID` (FK → `gyms`,
`ON DELETE SET NULL`, nullable — NULL for non-gym spend), `stage cost_stage` (enum `search | transcript |
tag | enrich | embed | scan`, all values up front — no `ADD VALUE` dance), `model TEXT`, `cost_usd DOUBLE
PRECISION`, `breakdown JSONB` (USD component map), `note`, `created_at`. Indexed on `gym_id`, `run_id`,
`source`. A cost row is matched back to its source table via **`(source, run_id)`**. Service-role-written
only: RLS enabled, public SELECT (`anon`, `authenticated`), INSERT/UPDATE/DELETE revoked from
`authenticated`.

**`member_activities.activity_type` is a `member_activity_type` enum** (`class_attended | rank_changed |
video_clicked`), declared in `member_activities.sql` — no longer free-text VARCHAR. The table stays
append-only (REVOKE UPDATE for `authenticated`); the seed emits `class_attended` in the loop plus one
`rank_changed` anchor per ranked member (`video_clicked` is a valid value but not seeded — no grounded
`activity_info` shape).

The Postgres enums are mirrored in `python_data/schema/`: `video.py` (`VideoRunStatus`),
`cost.py` (`CostSource`, `CostStage`), and `member_activity.py` (`MemberActivityType`).
`immutable_columns.py` carries `VIDEO_RAG` / `MEMBER_VIDEO_RECS` / `COST_LOG` frozensets and the four
`video_profile_*` columns in `MEMBERS`.

## Structure
- `schemas/` — source-of-truth SQL for each table (DDL, constraints, indexes, triggers)
- `access_rules/` — RLS policies, REVOKE/GRANT statements for each table (loaded after all schemas to avoid circular dependencies)
- `migrations/` — hand-authored migration files (see *Schema workflow*; an unapplied one may be edited in place, an already-applied one never)
- `python_data/schema/` — shared Python enums, Pydantic models, and immutable column definitions used by both the seeding scripts and the FastAPI backend
- `schema_db_diagram.io` — dbdiagram.io markup; always update this file when adding, removing, or renaming columns/tables
- `seed.mermaid` — Mermaid map of the end-state spread of everything `make seed` (`python_data/main.py`) creates (counts, types, proportions per gym); a living doc — keep it in sync with `constants.py` and the `python_data/` generators whenever the seed's outputs change. Author/edit it with the `mermaid-creation` skill (top-down `TB`, sibling-only edges, render + `check_siblings.py` + Mermaid-9 parse).
- `config.toml` — Supabase project config
