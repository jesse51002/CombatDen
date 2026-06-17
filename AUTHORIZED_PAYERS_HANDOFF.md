# Authorized Payers + Waiver + Anchor-Freeze — HANDOFF (light brief)

> The payer feature (PR #23) is **MERGED into `thru`**. This doc is the NEXT task.
> **The user will give the next agent a deeper plan — this is a light brief to orient, NOT a full plan. Don't over-engineer off it.**

## Worktree
The old `paid-by-member-id` worktree + branch are being deleted (work merged). Start the new task in a **fresh worktree branched off `thru`** (which now contains the merged payer work: `account_linked_to_id` authorization layer + per-membership `paid_by_member_id` billing key).

## The task (4 parts)
1. **Many authorized payers per member.** Drop the single-parent `account_linked_to_id` assumption → a member can have MANY authorized payers, AND be an authorized payer for others while also having their own. Multi-level composes cleanly because billing is per-membership via `paid_by_member_id`. "Authorized payer" stays the **authorization layer only**; `paid_by_member_id` stays the billing key.
2. **Waiver gate before adding an authorized payer.** A default waiver that is **undeletable but editable**, living in the **existing gym-level waivers feature** (editable by any gym employee — no role gate). Must be signed **before** a link is created. Signed by the **authorized payer (X)**, **once per link** → a junction table `(member_id, payer_member_id, signed_at, waiver_version)`. This is the one place we accept a junction table over the usual jsonb-array preference (per-link signature/audit).
3. **Drop the guardrails.** Adding an authorized payer no longer needs the "no active memberships" / billing-state checks. Update the CRM linking flow + the Authorized-Payer UI to match.
4. **Anchor-based freeze, per-membership.** Store the billing anchor (`billing_cycle_anchor`) in our DB so we **never use Stripe's `pause_collection`**. Freeze becomes **per-membership** (freeze individual memberships, not just the whole payer sub). On resume, restore exact billing from the stored anchor so the billing date is unchanged. **Enable `billing_cycle_anchor` to be passed ONLY at subscription creation** (not on updates).

## Locked decisions (asked this session)
- Waiver signer = **authorized payer (X)**.
- Waiver frequency = **once per link** (→ junction table).
- Freeze granularity = **per-membership**.
- Waiver home = **gym-level, existing waivers feature**, undeletable, editable by any employee.

## Codebase pointers (post-merge, on `thru`)
- Authorization rule: `FastApiBackend/src/memberships/service/memberships_base.py::_assert_payer_allowed` ("self or linked parent" → "self or ∈ authorized payers").
- Single-parent link to replace: `members.account_linked_to_id` (`Database/supabase/schemas/members.sql`) + CRM `MemberDetailResponse.linkedToAccount` / `linkedAccounts`.
- Waivers feature: CRM `features/memberships/.../waiver_editor_screen.dart` + `MembershipsRepository` waiver/signature methods; backend waivers + `signatures/by-member`.
- Freeze: `FastApiBackend/src/memberships/service/memberships_freeze.py` (sets a freeze window → `pause_collection` via `src/sync/service/sync_freeze.py`); `member_memberships_status` view derives `frozen` from the freeze window keyed on `paid_by_member_id`. Sub creation/anchor lives in the `src/sync/` declarative engine.
- Authorized-Payer UI built this round (reuse/extend): `CRM/.../sections/linked_accounts_section.dart` ("Authorized Payer" / "Authorized to pay for", Add/Unlink Authorized Payer), freeze dialog `pays_for` impact list, per-payer Invoices card.

## Process guardrails
- Engine + memberships edits = **one approved piece at a time** (FastApiBackend `sync-guide` rule); billing-critical, human-in-the-loop.
- Never commit `.venv`/`.env` symlinks. CRM: hand-format (no `dart format`); `flutter analyze` + `flutter test` are the gates; run `build_runner` after model changes. SQL in files, `CAST(:p AS type)`.
- Shared local Supabase may need a clean `db reset` (cross-branch drift).
