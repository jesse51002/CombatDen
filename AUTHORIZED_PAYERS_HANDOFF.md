# Authorized Payers + Waiver Gate + Per-Membership Anchor Freeze — HANDOFF

Picks up an in-progress, billing-critical feature. **Read this top-to-bottom, then
the detailed plan at `~/.claude/plans/parsed-mapping-lighthouse.md`** (the canonical
roadmap — Context, locked decisions, every piece). This doc is the *current-state +
next-steps* snapshot.

## Hard rules (from the repo CLAUDE.md files — do not violate)
- **`src/sync/` + `src/memberships/` are billing-critical: one approved piece at a time,
  never a big sweep. Propose → wait → write, per piece.** Part 4 (freeze) especially.
- **No assumptions:** when a decision has >1 reasonable answer, ASK and wait. (The user
  has answered many; they're recorded below + in the plan.)
- **Never run migrations or the seed** (`supabase db reset`, `python python_data/main.py`).
  The USER runs them. Edit schema files in `Database/supabase/schemas/` + `access_rules/`;
  **hand-write** migrations (delegate to a Sonnet sub-agent per `Database/CLAUDE.md`), never
  `db diff`.
- **No inline SQL / prompts** — SQL in `.sql` files (`load_sql`), `CAST(:p AS T)` never
  `:p::T`. Backend gate is **`ruff check`**, hand-format (NOT `make format` — it churns).
- **Don't `git push` without asking.** Local commits at milestones are fine.

## Environment / worktree setup (IMPORTANT)
- Working in worktree **`.claude/worktrees/authorized-payers-waiver-freeze`** (branch
  `worktree-authorized-payers-waiver-freeze`), branched off local `thru`.
- This is a **background job**; isolation was achieved via `EnterWorktree` (it works on a
  fresh attempt — if `EnterWorktree(name)` fails once, retry; the guard is
  `worktree.bgIsolation:"worktree"` in `.claude/settings.local.json`).
- The worktree had **no backend venv/env** — they were symlinked/copied:
  `FastApiBackend/.venv` → symlink to the root checkout's; `FastApiBackend/.env` copied.
  Both gitignored. Run tools as **`.venv/bin/python -m ruff check …` / `-m pytest`** (console
  scripts have stale shebangs).
- Review via **`make meld`** (background; kill prior meld first as its OWN command:
  `flatpak kill org.gnome.meld 2>/dev/null; pkill -x meld 2>/dev/null; true`). Note `make
  meld` diffs the worktree vs the root checkout's HEAD (`thru`), so it shows ALL pieces, not
  just the latest.
- **Keep pulling `thru`** — the user merges PRs there often (already merged #24/#25/#26).
  `git fetch origin thru && git merge thru`.

## The feature (4 parts)
1. **Many authorized payers per member** — replace single-parent `account_linked_to_id`
   with many-to-many `member_authorized_payers`. Billing is already per-membership
   (`paid_by_member_id`), so the engine doesn't change — only authorization + reads + UI.
2. **Waiver gate** — a payer must sign a gym default authorized-payer waiver BEFORE the link
   is created. Signed by the payer, once per link, atomically with the link.
3. **Drop link guardrails** — no "no active recurring" check, no single-parent hierarchy.
4. **Per-membership anchor-preserving freeze** — retire `pause_collection`; freeze = a sync
   read-filter; store the billing anchor; resume on the same anchor (NOT paid-time-shift).

## Locked decisions (user-confirmed this session)
- Authorization model: a **new `member_authorized_payers` junction** (member_id,
  payer_member_id, gym_id, signature_id, created_at; PK (member_id,payer_member_id)). The
  signature log records the event; the junction records the use.
- Signing: **atomic link-with-signature** (no separate sign endpoint).
- Default waiver: **seed-copy** — a shared platform default body (`.md`) copied once into
  each gym's own `gym_waivers` `is_default` row; each gym owns + versions its copy; no live
  platform template. (No FK loosening, no signature column rename.)
- Member-detail page: **scope to M + relationship rosters** (`authorized_payers` /
  `authorized_to_pay_for`) + keep `pays_for`; drop the single-parent family aggregation.
- Grouper (the NEXT task): **fully single-member** — see below.
- **Freeze (part 4):** stays **member/account-level** (window on `members`, DB schema
  UNCHANGED), but **re-keyed**: a member's freeze covers only THAT member's own memberships
  — the status view + sync filter key on the membership's **`member_id`**, not
  `paid_by_member_id`. Resume is **anchor-preserving** (same billing day, not
  paid-time-preserving). Freeze = remove the line from the desired set (sync filter); re-add
  respects the stored anchor (recreate the sub with the stored anchor when freezing dropped
  the last line).

## DONE (committed on this branch)
- `59fd893e` **Piece 1** — data model: `member_authorized_payers` table + access rules +
  `MemberAuthorizedPayerCreate` + immutable set; `gym_waivers.is_default` + ≤1-default index
  + `trg_prevent_default_waiver_removal`; `member_waiver_signatures` INSERT policy; config.toml
  load order; dbdiagram + `Database/CLAUDE.md`.
- `a86e7c06` **Piece 2A** — default-waiver foundation: shared body
  `Database/python_data/schema/default_authorized_payer_waiver.md` + loader `default_waiver.py`
  (used by backend + seed); `WaiversCreate.create_default_waiver` + `waivers_insert_default.sql`;
  new gyms seed-copy their default waiver via `GymsService` (DI + WaiversService); seed
  `generators/waivers.py` + `bootstrap/waivers.py` + main.py + seed.mermaid.
- `886e9ce8` **Piece 2B** — authorization cutover (signing primitive + link/unlink/check
  rework + `_assert_payer_allowed`/`_check_links` on the junction + guardrails dropped +
  contract changes + member-detail rework to M+rosters + seed link call + skills) PLUS two
  review refactors: `MembersBillingSupplementary` is now **request-scoped** (constructed with
  `(db_pool, gym_id, member_id)`, `load()`; detail service holds no mutable state), and
  `MembershipOverviewContext` was converted from a frozen dataclass to a **frozen pydantic
  model**. All ruff-clean + py_compile-clean. NOT yet runnable (needs the user's `db reset`).

## IMMEDIATE NEXT TASK — grouper "fully single-member" refactor (user-approved option)
File: `FastApiBackend/src/members/service/member_details/members_billing_grouper.py`
(+ `members_billing_schema.py` + `members_billing_detail_service.py`). Why: the member-detail
carousel now gets only the viewed member's rows, and the query does
`DISTINCT ON (member_id,gym_id,plan_id)` → each "plan group" is exactly ONE membership, so the
cross-member machinery is dead weight. Do BOTH:
1. **Flatten the cards.** `group_by_plan` → map each membership row to one flat
   `BillingMembershipInfo`. **Drop `paying_for: list[BillingPayingForMember]` and the
   `members: dict[..., BillingMembershipMemberInfo]`** — inline that single membership's fields
   (item_id, paid_by_member_id, end_date, cancel_date, on_outdated_price, base_cost,
   total_price, status, the per-cycle usage) directly onto `BillingMembershipInfo`. Likely
   **remove `BillingPayingForMember`** (and inline/remove `BillingMembershipMemberInfo`).
2. **Single-member overview.** Reduce `build_membership_overview` to the viewed member's own
   memberships only ("Paying $X/mo for N membership(s)" + frozen/overdue/trial/cancelled
   states). **Remove `OverviewKind`**, the `pays_for_others`/`beneficiary` sentences +
   `_paid_by_suffix`, and the cross-member fields on `MembershipOverviewContext`
   (`members_paid_for_count`, `own_payer_ids`, `kind`). The "who pays for whom" relationships
   already live in the rosters + `pays_for` list.
3. **Detail service** `members_billing_detail_service.py`: simplify `_build_overview_context`
   (drop the kind/payer-math), and drop now-unused helpers (`_member_paying_total` if only the
   overview used it; check). `_build_pays_for` STAYS (it's the kept `pays_for` list).
4. **CRM ripple (Piece 3):** the flatter `BillingMembershipInfo` (no `paying_for`/`members`)
   changes the response the CRM carousel consumes — note it for Piece 3.
Verify: `.venv/bin/python -m ruff check` + `py_compile`. Then present via meld.

## THEN — 2C: drop `account_linked_to_id`
Once nothing reads it. Remaining readers (verified): `members.sql` (column + FK + partial index
+ `enforce_linked_account_hierarchy` trigger), `Database/python_data/schema/member.py:43` +
`immutable_columns.py:54`, `members_management_get_member.sql` (projection),
`members_management_update_card.sql` + `members_management_unlink_payment.sql` (RETURNING),
`MembersBillingProfileResponse.account_linked_to_id` (`members_billing_schema.py:47`), dbdiagram,
`Database/CLAUDE.md` members note. Remove all; retire the trigger/index. (Freeze does NOT use it
— the status view keys freeze on `paid_by_member_id` today; 4a re-keys to `member_id`.)

## THEN — Piece 3 (CRM, Flutter)
`linked_accounts_section.dart` → render MANY authorized payers + MANY payees (both
directions); Add runs a **sign-waiver step** before linking; drop guardrail UI. Update
`member_repository.dart` + models (`member_detail_response.dart` swaps `linkedToAccount`/
`linkedAccounts` for `authorizedPayers`/`authorizedToPayFor`; the flatter membership card),
`link_parent_dialog.dart`. New contract: link `PUT /members/{id}/link` body
`{payer_member_id, signer_name, consent_acknowledged}`; unlink `DELETE …?payer_member_id=`;
check body `{payer_member_id}`. **#26 reworked the start-membership card dialogs**
(`custom_card_capture.dart` etc.) — re-read those (same surface). Gates: `flutter analyze` +
`flutter test` + `build_runner` after model changes; then `qa-crm`.

## THEN — Piece 4 (freeze), staged a–e (FINEST staging, billing-critical)
- **4a** re-key the `member_memberships_status` view's freeze owner from `paid_by_member_id`
  to the membership's `member_id` (window stays on `members`). **Re-verify the CURRENT view
  first** (`Database/supabase/schemas/member_memberships.sql` ~line 410).
- **4b** store the billing anchor in the DB (today computed at create in
  `payments_subscription_create.py`, not stored). Confirm home (payer row vs membership).
- **4c** freeze = sync read-filter: exclude a frozen member's memberships in
  `src/sync/sql/get_active_recurring.sql`; freeze/unfreeze re-sync each distinct billing payer;
  retire `PaymentSyncFreeze` + `pause_collection`.
- **4d** anchor-preserving re-add on resume (recreate sub with stored anchor when the last line
  was dropped).
- **4e** CRM per-member freeze UI.
- **#24/#25 interactions to compose with:** reconciler `SubscriptionOrphanSweep` (don't let it
  reap a mid-freeze/emptied sub), best-effort writeback, discount verify/revert, and #25's
  immutable rows + new-row/upsert writeback. **Re-read `sync-guide` + `reconciler-guide` +
  `memberships-guide` before touching 4a/4c/4d.**

## Cross-cutting follow-ups (not yet done)
- **Migration:** none written yet for Piece 1/2's schema. Dev `db reset` rebuilds from
  `config.toml schema_paths`. Hand-write ONE migration after the schema settles (after 2C),
  including a **backfill of default waivers for existing gyms** + (if any) existing links →
  `member_authorized_payers`. The user runs it.
- **Tests:** `tests/memberships/test_memberships_linked.py`, `test_memberships_link_check.py`,
  `test_payer_qa.py` assert the OLD single-parent model and must be rewritten to the new
  sign-gated many-to-many behavior. Deliberately NOT rewritten blind — they need the migrated
  DB to run (shared DB has `paid_by_member_id` NOT NULL drift; needs `db reset`). Rewrite +
  verify AFTER the user migrates. Also add the freeze test `PaymentRefactor.md §8` flags.

## Key skills to load
`memberships-guide` (lifecycle ops), `sync-guide` (the engine), `discounts-guide`,
`payments-guide`, `reconciler-guide`. All living docs — update in the same change.
