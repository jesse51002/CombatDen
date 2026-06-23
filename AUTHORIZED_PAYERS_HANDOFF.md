# Authorized Payers + Waiver Gate + Per-Membership Anchor Freeze — HANDOFF

In-progress, **billing-critical** feature on branch `worktree-authorized-payers-waiver-freeze`
(worktree `.claude/worktrees/authorized-payers-waiver-freeze`, off local `thru`). Read this
fully, then the roadmap at `~/.claude/plans/parsed-mapping-lighthouse.md`.

## TL;DR — where we are (2026-06-23)
- **Backend is DONE, committed, migrated, seeded, and test-validated end-to-end:** Pieces 1
  (data model), 2A (default waiver), 2B (auth cutover), 2C (drop `account_linked_to_id`), and
  the **grouper single-member flatten**. The **migration is written + applied** (you ran it),
  the seed runs (it created **22 real sign-gated authorized-payer links**), and the relevant
  integration tests pass (member-detail/grouper/2C SQL/waivers/start-auth).
- **REMAINING:** **Piece 3 (CRM/Flutter)** and **Piece 4 (per-membership anchor freeze)** —
  both NOT started. (The flake-fix sub-agent is DONE + committed — see §7.)
- Branch is **current with `thru @ 9aac5193` (#32)**, clean tree, **nothing pushed**.

---

## 0. HARD RULES (repo CLAUDE.md — violating these breaks review/billing)
- **`src/sync/` + `src/memberships/` = most critical code. ONE approved piece at a time, never
  a big sweep. Propose → wait → write.** Part 4 (freeze) especially. User reviews each piece in
  `make meld` before you continue. **No assumptions** — >1 reasonable answer ⇒ ASK (`AskUserQuestion`).
- **NEVER run** `supabase db reset` / `supabase migration` / `python python_data/main.py`. The
  USER runs migrations + seed. You edit `Database/supabase/schemas/*.sql` + `access_rules/*.sql`
  (+ `python_data/`). Migrations are **hand-written** (delegate to a Sonnet sub-agent per
  `Database/CLAUDE.md`), **never** `supabase db diff`. Always review the sub-agent's migration.
- **Don't silently inherit problems** (codebase CLAUDE.md): when you find a pre-existing
  bug/anti-pattern, surface it + propose a fix; don't copy it forward. (This is how the reprice
  #32 regression below got found + fixed.)
- **No inline SQL/prompts.** SQL in `.sql` files via `load_sql`. In `.sql` + dynamic SET use
  `CAST(:p AS TYPE)`, NEVER `:p::TYPE` (asyncpg 500s on the latter).
- Backend gate = **`.venv/bin/python -m ruff check <files>`** then hand-format. Do NOT
  `make format` (churns ~60 files). `py_compile` for syntax.
- **NEVER write tests around production bugs** (FastApiBackend/CLAUDE.md) — fix the prod code or
  surface the bug; don't bump timeouts / loosen asserts to hide a real defect.
- **No `git push` without asking.** Local commits at milestones are fine + expected.
- CRM (Flutter): **don't run `dart format`**; `flutter analyze` + `flutter test` are the gates;
  run `build_runner` after model changes.

## 1. ENVIRONMENT (this worktree is fully set up now)
- Runs as a **background job**; isolation via `EnterWorktree` (already isolated — edits work).
- **Env files ARE copied in** (gitignored): `FastApiBackend/.env`, `CRM/.env.dev`, `CRM/.env.prod`,
  `Database/python_data/.env`, `VideoService/.env(.prod)`, `ThemeService/.env`. If a fresh
  worktree is ever remade, re-copy from the root checkout (`/var/home/jm/Documents/CombatDen/codebase`).
- `FastApiBackend/.venv` is a **symlink** to the root checkout's venv. Run tools as
  `.venv/bin/python -m ruff/pytest/py_compile` (console shebangs are stale).
- **The local Supabase DB IS migrated (incl. this feature's migration) + seeded.** `member_authorized_payers`
  exists, `account_linked_to_id` is gone, 1 seeded gym (`tests/seed_constants.py`
  SEEDED_GYM_ID `21636369-8b52-9b4a-97b7-50923ceb3ffd`), ~100 members, 22 authorized-payer links.
- **Review:** `make meld` (run in BACKGROUND from the worktree root via `make -C <worktree> meld`;
  it self-kills prior meld). Diffs the worktree vs the ROOT checkout's HEAD (which tracks `thru`).
  If meld dies with Error 137 / empty window, it's a peer/contention pre-empt — relaunch, don't chase.
- **Pull `thru` often** — `git fetch origin thru && git merge FETCH_HEAD`. SEE §6: pulling thru
  now CONFLICTS on the grouper (the flatten vs thru's cross-member carousel) — a known re-apply routine.

## 2. THE FEATURE (4 parts) + LOCKED DECISIONS (all user-confirmed)
1. **Many authorized payers/member** — replaced single-parent `members.account_linked_to_id`
   with many-to-many `member_authorized_payers`. Billing stays per-membership
   (`member_memberships.paid_by_member_id`); the sync engine is UNCHANGED. **DONE.**
2. **Waiver gate** — payer signs a gym default authorized-payer waiver, atomically with link
   creation, once per link. **DONE.**
3. **Drop guardrails** — no "no-active-recurring" check, no single-parent hierarchy. **DONE.**
4. **Per-membership anchor freeze** — retire Stripe `pause_collection`; freeze = sync read-filter;
   store the billing anchor; resume on the SAME anchor. **NOT STARTED** (Piece 4, §9).

Decisions: junction `member_authorized_payers`; signature log records the *event*, junction
records the *use* (FK to the gating signature). Signing **atomic** with the link (no separate
endpoint). Default waiver = **seed-copy** (a shared platform body copied ONCE into each gym's own
`gym_waivers` `is_default` row; per-gym owned/versioned; no live platform template). Member-detail
carousel = **fully single-member** (one card per membership row; no cross-member grouping — the
"flatten", §4). Freeze (part 4) stays **member/account-level** (window on `members`, DB schema
UNCHANGED) but **re-keyed** to the membership's own `member_id` (not `paid_by_member_id`); resume
**anchor-preserving** (same billing day, NOT paid-time-shift).

## 3. THE DATA MODEL (live in the DB now)
`member_authorized_payers`: `(member_id [payee], payer_member_id [payer/signer], gym_id,
signature_id FK→member_waiver_signatures, created_at)`; PK `(member_id, payer_member_id)`; CHECK
`member_id<>payer_member_id`; composite FKs to `members(member_id,gym_id)` for both ids; indexes
`idx_authpayer_member`, `idx_authpayer_payer`. RLS: SELECT for gym staff + the 2 involved members;
INSERT/UPDATE/DELETE REVOKE'd (service_role/backend-managed).
`gym_waivers` gained `is_default` + `idx_gym_waivers_one_default` (≤1/gym) +
`trg_prevent_default_waiver_removal` (undeletable) + REVOKEs.
`member_waiver_signatures`: unchanged shape + a staff-INSERT RLS policy. `members.account_linked_to_id`
is **dropped** (column + FK + index + `enforce_linked_account_hierarchy()` fn/trigger gone);
`member_billing_profile` view recreated as `SELECT * … security_invoker`.

## 4. WHAT'S DONE (commits on this branch, newest first — `git log`)
- `65ad7429` **Tests:** link-helper rewrite to the sign-gated model (see §5).
- `01a6b749` **Fix reprice** missing `quantities` (thru #32 regression — see §8).
- `4b6adc90` **Migration** `Database/supabase/migrations/20260622233350_authorized_payers_waiver_and_drop_linked_account.sql`
  (Pieces 1/2A/2C DDL — reviewed line-by-line, applied cleanly).
- `215c008f` **2C** drop `account_linked_to_id` (schema/access/backend SQL projections/payer_resolver
  docstring/cleanup.py teardown/python_data/`schema_db_diagram.io`/`Database/CLAUDE.md`/3 skills).
- `a0d17edd` **Grouper flatten** (the carousel single-member rewrite, §4 below).
- `9ad76079` test factory `waivers_service` fix.
- earlier (pre-this-session): Piece 1 (`59fd893e`), 2A (`a86e7c06`), 2B (`886e9ce8`).
- Interleaved `thru` merges bring #28 refund, #29 proration, #30 paid_by/paid_for split,
  #31 CRM invoice-poll, #32 class-pack quantity.

**The grouper flatten (a0d17edd):** `members_billing_grouper.py` — `group_by_plan` →
`build_membership_cards` (one flat `BillingMembershipInfo` per row; usage keyed by **`item_id`**
post-#32). Deleted `BillingPayingForMember` + `BillingMembershipMemberInfo` + `paying_for`/`members`
map from the schema (inlined item_id/paid_by_member_id/end/cancel/on_outdated_price/flat class
usage). Removed `OverviewKind` + the cross-member overview builders; overview is single-self-pay.
`members_billing_detail_service.py` request-scoped + own-rows only; `members_billing_supplementary.py`
lost the dead `profiles_dict`. Pydantic unit tests in `tests/members/test_member_billing_overdue.py`.

**2B auth core (recap):** `memberships_linked.py::link_account(member, payer, *, signer_name,
consent_acknowledged)` — sign-gated, atomic (resolve gym default waiver → record signature → insert
junction). `unlink_account`, `check_link_account`. `_assert_payer_allowed` / `_check_links` query
the junction. New endpoints `PUT/DELETE/POST /members/{id}/link[/check]`. Error message is now
**"…has not authorized payer… — authorize them first…"** (was "link them first"). The link path is
a **pure DB change (no Stripe sync)**.

## 5. TEST STATE (validated this session against the migrated+seeded DB + real Stripe)
- **Green:** `tests/members/` (member-detail/grouper/2C SQL/management) + the e2e
  `tests/sync/mid_cycle/test_billing_detail_shows_applied_discount.py` + `tests/waivers/` + ~91 of
  `tests/memberships/`. Plus the seed's 22 sign-gated links = end-to-end proof.
- **Link-test rewrite (65ad7429):** `tests/helpers/db_writes.py::authorize_payer(db_pool, member,
  payer)` drives the REAL `MemberMembershipsLinked.link_account` flow; swapped into 6 files
  (`test_start_family`, `test_start_preview_one_time_leak`, `test_memberships_cash`,
  `test_memberships_update_price`, `test_one_time_family_sweep`, `test_memberships_cancel`) which
  previously used the deleted `member_memberships_link.sql`. Updated stale "link them first" asserts.
- `delete_member_data` (cleanup.py) now also deletes `member_authorized_payers` +
  `member_waiver_signatures` (FK-safe order). The 3 pure old link tests (`test_memberships_linked`,
  `test_memberships_link_check`, `test_payer_qa`) were DELETED (user's call) — **new sign-gated
  coverage for the link endpoints themselves is NOT yet written** (follow-up; the seed + the rewired
  family-start tests exercise the flow, but there's no dedicated link/unlink/check endpoint test).

## 6. ⚠️ THE `thru`-MERGE FRICTION (read before pulling thru)
`thru` is actively building the carousel on the **cross-member** model (paying_for/members map +
#30 paid_by/paid_for + #32 class-pack grouping) — the exact thing the **flatten removed**. So
**every `thru` pull conflicts on `members_billing_grouper.py` + `test_member_billing_overdue.py`**
(and sometimes the schema + memberships-guide + seed.mermaid). USER CHOSE: **keep the flatten,
re-apply over thru.** The routine (mostly auto-merges; you hand-resolve ~4 files):
- `member_details.sql`, `members_billing_detail_service.py`, `cycle_counts_bridge` auto-merge fine
  (my family_group/paid_by model + thru's #32 per-`item_id` rows + item_id-keyed usage).
- Grouper conflict → `git checkout --ours` it (the flatten) then re-apply the ONE #32 adaptation:
  usage keyed by `row["item_id"]` (not plan_id). Test conflict → `--ours` + add `item_id`/`start_date`
  to the `MembershipUsage` construction + key the lookup by item_id.
- memberships-guide/seed.mermaid → keep thru's #32 content, restore the many-to-many wording + the
  `w_default` node. Verify NO `account_linked_to_id` reappears in live code (grep), keep it purged.
- After resolving: ruff + `pytest tests/members/test_member_billing_overdue.py` + full `--collect-only`.

## 7. DONE: flake-fix (2 pre-existing thru timing-flakes) — committed `38e33b3a`
Both flakes (`test_phase_a_linked_child_self_pays_own_membership` + `test_mixed_cart_recurring_card_fails_at_billing`)
shared ONE root cause: the `stripe listen` forwarder delivers `invoice.paid` to the live backend,
whose handler INSERTs a `member_invoice_line_items` row FK'd to the test membership
(`fk_line_item_membership_gym`), racing the membership DELETE in `delete_member_data`. Because all
teardown deletes are one txn, the membership stays visible (READ COMMITTED) to the webhook's
connection until commit, so deleting line items earlier in the same txn didn't help.
**Fix (test-only, `tests/helpers/cleanup.py`):** `LOCK TABLE member_invoice_line_items IN EXCLUSIVE
MODE` at the start of the teardown txn — a concurrent webhook either commits first (our DELETE
catches it) or blocks until our commit (membership gone → backend FK violation → Stripe retry → no
member → harmless early return). **Not masking a bug** — the production webhook path is untouched and
already handles the FK-violation retry. Verified: test_phase_a 5/5 isolated, test_start_family 12/12
together (107s), test_mixed_cart 5/5 (~11s each). Reviewed (diff confined to cleanup.py, ruff clean)
before commit.

## 8. CROSS-CUTTING NOTES
- **Reprice #32 regression (fixed, flag to #32's owner):** thru's #32 added a REQUIRED `quantities`
  param to `member_memberships_insert.sql` + updated the start path but NOT
  `MemberMembershipsReprice._insert_successor` → every reprice 500'd. Fixed in `01a6b749`
  (recurring is always qty 1 → `[1]`). When this branch merges to thru, this fix matters there too.
- The whole feature still needs to **merge back to thru** eventually (it replaces `account_linked_to_id`
  repo-wide). Not done; coordinate with the user.

## 9. WHAT'S NEXT (each its own propose→approve→write piece)

### Piece 3 — CRM (Flutter, `CRM/lib/features/...`) — NOT STARTED
The CRM still consumes the OLD shapes and is **runtime-broken against the new backend** until done:
- `member_details/data/models/`: `member_detail_response.dart` still reads `linked_to_account`
  (removed by 2B → now `authorized_payers` + `authorized_to_pay_for`); `membership_info.dart` reads
  the `members` map + `paying_for` list (removed by the flatten → now flat fields:
  `item_id`/`paid_by_member_id`/`end_date`/`cancel_date`/`on_outdated_price`/`class_count`/`classes_used`/`classes_remaining`).
  `members_management_response.dart` has a now-dead `accountLinkedToId` (drop it). Run `build_runner`.
- New contract: link `PUT /members/{id}/link` `{payer_member_id, signer_name, consent_acknowledged}`;
  unlink `DELETE …?payer_member_id=`; check `POST …/link/check {payer_member_id}`.
- `presentation/sections/linked_accounts_section.dart` → render MANY authorized payers + MANY payees
  (both directions); "Add" runs a **sign-waiver step** (show waiver text + capture signer name +
  consent) BEFORE creating the link; remove guardrail UI. Reuse `waiver_editor_screen.dart` for the
  default waiver (flagged undeletable). #30/#31/#32 reworked nearby billing widgets — re-read.
- Gates: `flutter analyze` + `flutter test`; then the `qa-crm` skill (screenshot the pages).

### Piece 4 — per-membership anchor freeze (billing-critical, finest staging) — NOT STARTED
Staged a–e, each its own propose/approve/write. RE-READ `sync-guide` + `reconciler-guide` +
`memberships-guide` + `payments-guide` first; they've all moved with #28–#32.
- **4a** re-key the `member_memberships_status` view freeze owner from `paid_by_member_id` → the
  membership's own `member_id` (window stays on `members`). Update FastApiBackend/CLAUDE.md
  Computed-Status note + the memberships-guide freeze note. (NOTE: the live view currently keys on
  `paid_by_member_id`; confirm post-#32.)
- **4b** store the billing anchor in our DB (computed-not-stored today in
  `payments_subscription_create.py`). Confirm storage home with the user.
- **4c** freeze = sync read-filter on the subject `member_id` in `src/sync/sql/get_active_recurring.sql`;
  freeze/unfreeze = DB-first member mutations + re-sync each distinct payer; retire `PaymentSyncFreeze`
  + `payments_subscription_freeze.py` + `pause_collection`.
- **4d** anchor-preserving re-add on resume (recreate sub with stored anchor when freezing dropped
  the last line — anchor is create-only).
- **4e** CRM per-member freeze UI.
- Compose with: reconciler `SubscriptionOrphanSweep` (don't reap a mid-freeze/emptied sub),
  best-effort writeback, discount verify/revert, #25 immutable rows + new-row/upsert writeback,
  #30 paid_by/paid_for, #32 quantity. `PaymentRefactor.md` §3/§4 are the old roadmap — remove when
  the anchor-preserving variant ships.

### Other follow-ups
- Write dedicated sign-gated tests for the link/unlink/check ENDPOINTS (§5 gap).
- Add the freeze "drop one member's line off a shared consolidated sub" test (`PaymentRefactor.md §8`).
- Living docs to update WITH the code: `sync-guide` + `payment_sync.mermaid`, `memberships-guide`,
  `payments-guide`, `FastApiBackend/CLAUDE.md` + `README.md` + `architecture.mermaid`, `discounts-guide`
  (freeze-during-discount-lifetime note).

## 10. SKILLS TO LOAD
`memberships-guide`, `sync-guide`, `discounts-guide`, `payments-guide`, `reconciler-guide` (all
living docs — update in the same change as code). `qa-crm` for Piece 3. Plan:
`~/.claude/plans/parsed-mapping-lighthouse.md`.
