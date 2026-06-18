# Authorized Payers + Waiver Gate + Per-Membership Anchor Freeze — HANDOFF

In-progress, **billing-critical** feature. Read this fully, then the canonical roadmap at
`~/.claude/plans/parsed-mapping-lighthouse.md`. This doc = current state + exact next steps so
you can execute without re-exploring. Branch: `worktree-authorized-payers-waiver-freeze`
(worktree `.claude/worktrees/authorized-payers-waiver-freeze`, off local `thru`).

---

## 0. HARD RULES (repo CLAUDE.md — violating these breaks review/billing)
- **`src/sync/` + `src/memberships/` = most critical code. ONE approved piece at a time,
  never a big sweep. Propose → wait → write.** Part 4 (freeze) especially. The user reviews
  each piece in `make meld` and says "looks good" before you continue.
- **No assumptions:** >1 reasonable answer ⇒ ASK + wait. Use `AskUserQuestion`.
- **NEVER run** `supabase db reset` / `supabase migration` / `python python_data/main.py`.
  The USER runs migrations + seed. You only edit `Database/supabase/schemas/*.sql` +
  `access_rules/*.sql` (+ `python_data/`). Migrations are **hand-written** (delegate to a
  Sonnet sub-agent per `Database/CLAUDE.md`), **never** `supabase db diff`.
- **No inline SQL/prompts.** SQL lives in `.sql` files loaded via `load_sql`. In `.sql` and in
  dynamic SET clauses use `CAST(:p AS TYPE)`, NEVER `:p::TYPE` (asyncpg `text()` 500s on the
  latter).
- Backend lint gate = **`.venv/bin/python -m ruff check <files>`**, then **hand-format**
  additions. Do NOT run `make format` (it churns ~60 unrelated files). `py_compile` for syntax.
- **No `git push` without asking.** Local commits at milestones are fine + expected.
- CRM (Flutter): **don't run `dart format`** (repo isn't format-clean); hand-format;
  `flutter analyze` + `flutter test` are the gates; run `build_runner` after model changes.

## 1. ENVIRONMENT / WORKTREE (read before doing anything)
- This runs as a **background job**. Isolation is via `EnterWorktree` — it works; if
  `EnterWorktree(name)` fails once with a "subagent cwd override" error, **just retry** (or
  `git worktree add` manually then `EnterWorktree(path=…)`). The guard is
  `worktree.bgIsolation:"worktree"` in `.claude/settings.local.json`.
- A fresh worktree has **no backend venv/env**. Already fixed here:
  `FastApiBackend/.venv` is a **symlink** to the root checkout's `.venv`; `FastApiBackend/.env`
  was copied. Both gitignored (never commit). If missing, recreate:
  `ln -s <root>/FastApiBackend/.venv FastApiBackend/.venv` + `cp <root>/FastApiBackend/.env .`.
- Run backend tools as `.venv/bin/python -m ruff check …` / `-m pytest …` (console-script
  shebangs are stale — `poetry run`/`ruff` directly fail).
- **Review:** `make meld` (run in BACKGROUND). Kill any prior meld FIRST, as its OWN command:
  `flatpak kill org.gnome.meld 2>/dev/null; pkill -x meld 2>/dev/null; true` (use `-x`, not
  `-f`). `make meld` diffs the worktree vs the ROOT checkout's HEAD (`thru`) → it shows ALL
  unmerged pieces, not just the latest; point the user at the specific files.
- **Pull `thru` often** — the user merges PRs there frequently (already merged #24 resilience,
  #25 membership-immutability+reprice-as-tasks, #26 card-at-checkout). `git fetch origin thru
  && git merge thru`; resolve conflicts (Database/CLAUDE.md tends to conflict — keep both sides'
  bullets).

## 2. THE FEATURE (4 parts) + LOCKED DECISIONS (all user-confirmed)
1. **Many authorized payers/member** — replace single-parent `members.account_linked_to_id`
   with many-to-many `member_authorized_payers`. Billing is already per-membership
   (`member_memberships.paid_by_member_id`), so the sync engine is UNCHANGED; only the
   authorization layer + family-reads + UI change.
2. **Waiver gate** — payer signs a gym default authorized-payer waiver, atomically with link
   creation, once per link.
3. **Drop guardrails** — no "no-active-recurring" check, no single-parent hierarchy.
4. **Per-membership anchor freeze** — retire Stripe `pause_collection`; freeze = sync
   read-filter; store the billing anchor; resume on the SAME anchor.

Decisions:
- **Data model:** new junction `member_authorized_payers`. Signature log records the *event*;
  the junction records the *use* (references the gating signature by FK).
- **Signing:** **atomic link-with-signature** — no separate sign endpoint.
- **Default waiver:** **seed-copy** — a shared platform default body (`.md`) copied ONCE into
  each gym's own `gym_waivers` `is_default` row; each gym owns+versions its copy; no live
  platform template; **no signature-FK loosening, no column rename**.
- **Member-detail page:** scope to **M + relationship rosters** (`authorized_payers` /
  `authorized_to_pay_for`) + keep `pays_for`; drop the single-parent family aggregation.
- **Grouper (next task):** **fully single-member** (cards flattened + overview single-member) —
  §5.
- **Freeze (part 4):** stays **member/account-level**, window on `members` (**DB schema
  UNCHANGED**), but **re-keyed**: a member's freeze covers only THAT member's own memberships —
  status view + sync filter key on the membership's **`member_id`**, NOT `paid_by_member_id`.
  Resume **anchor-preserving** (same billing day, NOT paid-time-shift). Freeze removes the line
  from the sync's desired set; re-add respects the stored anchor (recreate sub w/ stored anchor
  if freezing dropped the last line).

## 3. THE DATA MODEL (what Piece 1 created)
`Database/supabase/schemas/member_authorized_payers.sql` (+ `access_rules/` sibling):
```
member_authorized_payers
  member_id        UUID  -- the member being paid for (Y)
  payer_member_id  UUID  -- the authorized payer / signer (X)
  gym_id           UUID  FK gyms
  signature_id     UUID  FK member_waiver_signatures (the gating signature)
  created_at       TIMESTAMPTZ
  PK (member_id, payer_member_id)            -- one authorization per pair
  CHECK member_id <> payer_member_id
  composite FKs (member_id,gym_id) + (payer_member_id,gym_id) -> members(member_id,gym_id)
  idx_authpayer_member (member_id, gym_id) ; idx_authpayer_payer (payer_member_id, gym_id)
```
RLS: `authenticated` SELECT (gym staff + the two involved members); INSERT/UPDATE/DELETE
**REVOKE'd** (service_role-only, backend-managed). Loads AFTER members + member_waiver_signatures
in `config.toml schema_paths`.

`gym_waivers` gained `is_default BOOLEAN DEFAULT FALSE` + `idx_gym_waivers_one_default`
(partial unique, ≤1 default/gym) + `trg_prevent_default_waiver_removal` (blocks archiving/
deleting a default, and `is_default` toggles) + REVOKE on is_default INSERT/UPDATE.

`member_waiver_signatures` kept its shape (`member_id` = the signer) — Piece 1 only ADDED the
INSERT RLS policy ("Gym staff can record waiver signatures", `is_gym_admin_or_owner`).

Shared default body: `Database/python_data/schema/default_authorized_payer_waiver.md` +
`default_waiver.py` (`DEFAULT_AUTHORIZED_PAYER_WAIVER_NAME` +
`default_authorized_payer_waiver_body()`), imported by BOTH backend (via
`src/shared/db_schema_path.py`) and the seed. The `.md` body is a placeholder — the founder
can refine it; it's editable per gym.

## 4. WHAT'S DONE (commits on this branch, newest first)
- `920374e4` this handoff.
- `886e9ce8` **Piece 2B** — authorization cutover + member-detail rework + 2 review refactors.
- `a86e7c06` **Piece 2A** — default-waiver foundation.
- `59fd893e` **Piece 1** — data model.
- `52046618`/`ede1ba73`/`b1c8f914` — `thru` merges (#26/#25/#24).

### Backend signing (waivers) — done
- `src/waivers/sql/member_waiver_signatures_insert.sql` (INSERT, RETURNING signature_id) +
  `waiver_default_for_member.sql` (resolve a member's gym default waiver current version +
  content_hash).
- `WaiversSignatures.record_signature(session, *, gym_id, signer_member_id, waiver_id,
  waiver_version_id, signer_name, consent_acknowledged, content_hash, ip_address=None,
  user_agent=None) -> UUID` — runs in the CALLER's txn (no commit) so the signature + the
  authorization land atomically. `WaiversSignatures.get_default_waiver_for_member(member_id)
  -> WaiverDefaultInfo`. Both re-exposed on the `WaiversService` facade.
- `waivers_schema.py`: added `WaiverDefaultInfo(gym_id, waiver_id, version_id, content_hash)`.
- Stale "Phase 2 not implemented" docstrings dropped (router/schema/signatures).

### Backend auth core (memberships) — done
- `memberships_linked.py` (`MemberMembershipsLinked`, self-contained, two-account lock,
  injects `WaiversService`):
  - `link_account(member_id, payer_member_id, *, signer_name, consent_acknowledged,
    ip_address=None, user_agent=None)` — reject self / require consent → lock([member, payer])
    → `_run_link_check` (payer exists / same gym / not already authorized) →
    `get_default_waiver_for_member` → ONE txn: `record_signature(session, signer=payer) +
    INSERT member_authorized_payers`.
  - `unlink_account(member_id, payer_member_id)` → DELETE the junction row (RETURNING; raise if
    none). `check_link_account(member_id, payer_member_id)` → simplified pre-flight.
  - `_run_link_check` (loads `member_authorized_payers_link_check.sql`), `_link_block_reason`.
- `memberships_base.py::_assert_payer_allowed` → self OR exists in
  `member_authorized_payers_get.sql`.
- `memberships_start_validation.py::_check_links` → batch
  `member_authorized_payers_check_batch.sql` (existence + gym + `authorized`).
- New SQL (memberships/sql/): `member_authorized_payers_get.sql`, `_insert.sql`, `_delete.sql`,
  `_check_batch.sql`, `_link_check.sql`. **Deleted** (6): `member_memberships_link.sql`,
  `_unlink.sql`, `_get_account_link.sql`, `_link_check.sql`, `_start_account_links.sql`,
  `_active_recurring.sql`.
- Facade `memberships_service.py`: injects `waivers_service`, passes to `MemberMembershipsLinked`,
  delegations updated. DI `dependencies.py`: `member_memberships_service` provider gains
  `waivers_service=waivers_service` (and `gyms_service` gained it in 2A).
- Contract (`memberships_schema.py` + `members_router.py`): `MembersBillingLinkRequest` now
  `{payer_member_id, signer_name, consent_acknowledged}` (+ validator); new
  `MembersBillingLinkCheckRequest{payer_member_id}`. Endpoints (in `members_router.py`):
  `PUT /api/v1/members/{member_id}/link` (body=link req), `DELETE /…/link?payer_member_id=`,
  `POST /…/link/check` (body=check req). NOTE: ip/user_agent NOT captured (passed None) —
  could add via `fastapi.Request` later.

### Backend member-detail (members) — done
- `member_details.sql`: family CTE is now **M ∪ {members M pays for}** (UNION on
  `member_memberships_status.paid_by_member_id = :member_id`); removed `account_linked_to_id`
  from CTE + SELECT. Still reads `member_billing_profile` (stripe-complete only — pre-existing).
- New rosters: `member_details_authorized_payers.sql` (junction by member_id → payers) +
  `member_details_authorized_to_pay_for.sql` (by payer_member_id → payees).
- `MembersBillingSupplementary` is **request-scoped** now: `__init__(db_pool, gym_id,
  member_id)`, `load()` (was `fetch_all(gym_id, member_id)`), `_reset` removed; added
  `_fetch_roster` + `authorized_payers`/`authorized_to_pay_for` properties; kept
  `profiles_dict` (the grouper still uses it); **removed dead `get_family_profiles`**.
- `members_billing_detail_service.py`: builds a LOCAL `supplementary` per call (no instance
  state); family scope = M + paid-for; `authorized_payers`/`authorized_to_pay_for` from the
  rosters; card-on-file from M's OWN row (removed `_find_parent_profile`); `_build_response`
  takes `redeemed_rewards` as a param.
- `members_billing_schema.py`: `MemberBillingDetailResponse` swapped `linked_to_account` +
  `linked_accounts` for `authorized_payers` + `authorized_to_pay_for` (both
  `list[BillingLinkedAccount]`); kept `pays_for`. (`MembersBillingProfileResponse` STILL has
  `account_linked_to_id` — that's a different response; removed in 2C.)
- `MembershipOverviewContext` (in `members_billing_grouper.py`) converted dataclass → frozen
  pydantic `BaseModel` (`model_config = ConfigDict(frozen=True)`).

### Seed — done
- `api_creation/memberships.py::_link_child` now PUTs `{payer_member_id, signer_name:
  f"{parent.first_name} {parent.last_name}", consent_acknowledged: True}` (backend signs +
  authorizes). 2A added `bootstrap/waivers.py` + `generators/waivers.py` (one default waiver +
  v1 + pointer per gym, content_hash = sha256(body)) wired into `main.py` per-gym loop.

### Skills — done
`memberships-guide` (link/unlink row + start-op language → many-to-many sign-gated) +
`sync-guide` (authorization-layer mentions → `member_authorized_payers`; caller-contract table)
updated.

## 5. IMMEDIATE NEXT TASK — grouper "fully single-member" (user-approved)
Files: `members_billing_grouper.py`, `members_billing_schema.py`,
`members_billing_detail_service.py`. WHY: carousel now gets only the viewed member's rows AND
`member_details.sql` does `DISTINCT ON (member_id,gym_id,plan_id)` ⇒ each "plan group" is
exactly ONE membership; the cross-member machinery is dead.
1. **Flatten cards.** `group_by_plan` → one flat `BillingMembershipInfo` per membership.
   **Drop `paying_for: list[BillingPayingForMember]` + `members: dict[…,
   BillingMembershipMemberInfo]`**; inline that membership's fields onto `BillingMembershipInfo`
   (item_id, paid_by_member_id, end_date, cancel_date, on_outdated_price, base_cost,
   total_price, status, the per-cycle usage from `usage_lookup`). Likely DELETE
   `BillingPayingForMember`; inline/remove `BillingMembershipMemberInfo`. Check `_build_paying_for`
   (lines ~304+, I didn't read its tail) for the usage shape to preserve.
2. **Single-member overview.** Reduce `build_membership_overview` to M's own memberships only
   ("Paying $X/mo for N membership(s)" + frozen/overdue/trial/cancelled states). DELETE
   `OverviewKind`, `_overview_pays_for_others`, `_overview_beneficiary`, `_paid_by_suffix`, and
   the cross-member fields on `MembershipOverviewContext` (`members_paid_for_count`,
   `own_payer_ids`, `kind`). Keep `_state_phrase`, `_count_suffix`, `_display_status`,
   `_collect_plan_discounts`.
3. **Detail service:** simplify `_build_overview_context` (drop kind/payer-math + the
   `members_paid_for`/`own_payer_ids` computation); drop now-unused helpers (`_member_paying_total`
   if only the overview used it). **`_build_pays_for` STAYS** (the kept `pays_for` list).
4. **CRM ripple:** the flatter `BillingMembershipInfo` changes what the CRM carousel consumes —
   note for Piece 3.
Verify: `.venv/bin/python -m ruff check` + `py_compile`; present via meld.

## 6. THEN — 2C: drop `members.account_linked_to_id`
Once nothing reads it. Full reader set to clean: `members.sql` (column + FK
`fk_member_linked_account` + partial index `idx_members_account_linked_to` +
`enforce_linked_account_hierarchy` trigger+function), `python_data/schema/member.py:43`,
`python_data/schema/immutable_columns.py:54`, `members_management_get_member.sql` (projection),
`members_management_update_card.sql` + `members_management_unlink_payment.sql` (RETURNING),
`MembersBillingProfileResponse.account_linked_to_id` (`members_billing_schema.py:47`),
`schema_db_diagram.io`, `Database/CLAUDE.md` members note. Freeze does NOT depend on it (status
view keys on `paid_by_member_id` today; 4a re-keys to `member_id`).

## 7. THEN — Piece 3 (CRM / Flutter, `CRM/lib/features/...`)
- `member_details/presentation/sections/linked_accounts_section.dart` → render MANY authorized
  payers + MANY payees (both directions); "Add" runs a **sign-waiver step** (show waiver text +
  capture signer name + consent) BEFORE creating the link; remove guardrail UI.
- Models: `member_detail_response.dart` (swap `linkedToAccount`/`linkedAccounts` →
  `authorizedPayers`/`authorizedToPayFor`; flatten the membership card to match the new
  `BillingMembershipInfo`), `linked_account.dart`, `link_parent_dialog.dart`,
  `member_repository.dart`. Run `build_runner`.
- New contract: link `PUT /members/{id}/link` body `{payer_member_id, signer_name,
  consent_acknowledged}`; unlink `DELETE …?payer_member_id=`; check body `{payer_member_id}`.
- #26 reworked the start-membership card dialogs (`custom_card_capture.dart`,
  `one_time_card_dialog.dart`, `saved_card_section.dart`) — re-read; same surface.
- Gates: `flutter analyze` + `flutter test`; then `qa-crm`.

## 8. THEN — Piece 4 (freeze) — STAGED a–e, finest grain, billing-critical
- **4a** re-key `member_memberships_status` view freeze owner `paid_by_member_id` →
  membership's `member_id` (window stays on `members`). RE-VERIFY the current view first
  (`Database/supabase/schemas/member_memberships.sql` ~line 393-411). Update `FastApiBackend/
  CLAUDE.md` Computed-Status note.
- **4b** store the billing anchor in DB (today computed-not-stored in
  `payments_subscription_create.py` via `_next_monthly_anchor_timestamp`). Confirm home
  (payer row vs membership) with the user.
- **4c** freeze = sync read-filter on the subject `member_id` in
  `src/sync/sql/get_active_recurring.sql`; freeze/unfreeze write the member's window then
  re-sync EACH distinct payer billing that member's memberships; retire `PaymentSyncFreeze` +
  `payments_subscription_freeze.py` + `pause_collection`.
- **4d** anchor-preserving re-add (recreate sub with stored anchor when freezing dropped the
  last line — anchor is create-only).
- **4e** CRM per-member freeze UI (acts on a member; surface which payers' bills change).
- **Compose with #24/#25:** reconciler `SubscriptionOrphanSweep` (don't reap a mid-freeze/
  emptied sub), best-effort writeback, discount verify/revert, #25 immutable rows +
  new-row/upsert writeback. RE-READ `sync-guide` + `reconciler-guide` + `memberships-guide`
  before 4a/4c/4d. `FastApiBackend/PaymentRefactor.md` §3/§4 are the original roadmap — remove
  them when the anchor-preserving variant ships.

## 9. CROSS-CUTTING FOLLOW-UPS (not done — do at the right time)
- **Migration:** NONE written for Piece 1/2. Dev `db reset` rebuilds from `config.toml
  schema_paths`. Hand-write ONE migration AFTER the schema settles (post-2C) — include a
  **backfill of `gym_waivers` default waivers for existing gyms** and (if any prod data) a
  backfill of existing `account_linked_to_id` links → `member_authorized_payers` (these need a
  signature row each — decide how with the user). User runs it.
- **Tests:** `tests/memberships/test_memberships_linked.py`, `test_memberships_link_check.py`,
  `test_payer_qa.py` assert the OLD single-parent model → must be REWRITTEN to the new
  sign-gated many-to-many behavior. Deliberately NOT rewritten blind (can't run: shared DB has
  `member_memberships.paid_by_member_id NOT NULL` drift → needs `db reset`; + the new schema).
  Rewrite + verify AFTER the user migrates. Add a freeze "drop one member's line off a shared
  sub" test (`PaymentRefactor.md §8` flags it missing). Tests run against a REAL shared Supabase
  + Stripe test account — use the `created` fixture for cleanup (see `FastApiBackend/CLAUDE.md`).
- **`make meld`** still wired; the user reviews each piece there.

## 10. SKILLS TO LOAD
`memberships-guide`, `sync-guide`, `discounts-guide`, `payments-guide`, `reconciler-guide` (all
living docs — update in the same change as code). Plan: `~/.claude/plans/parsed-mapping-lighthouse.md`.
