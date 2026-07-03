---
name: waivers-guide
description: >-
  The single source of truth for the CombatDen waiver e-signature system — the
  three-table model (gym_waivers catalog identity with the waiver_type enum
  (payer_auth = the gym's one undeletable authorized-payer agreement | custom,
  expandable), gym_waiver_versions conditionally-immutable TEMPLATE bodies with
  a per-version requires_resign flag, member_waiver_signatures the append-only
  e-sign audit that freezes the rendered body), the ONE signing service
  WaiversSignatures.sign_waiver (version-lock on the echoed version +
  {{placeholder}} rendering + full-rendered-body snapshot, its own committed txn),
  the standalone signing endpoint POST /api/v1/waivers/{waiver_id}/signatures, the
  authorize-payer LINK as one request that REUSES sign_waiver (rendering payer +
  payee names, not atomic), the membership-START waiver gate (_check_waivers + the
  requires_resign re-sign FLOOR, all plan types, 422 with the unsigned list,
  surfaces in preview), the CHECK-IN waiver gate (the checkin domain's
  unsigned_waiver warning: kiosk-reject / staff warn-first with override;
  reservations deliberately ungated), the plans-only-custom guard (_validate_waiver_ids at plan
  write time), archive semantics (payer_auth never archivable via the API; a
  custom archive strips its id from every plan's waiver_ids), parametrization
  (the {{placeholders}} catalog waiver_parameters.py, backend auto-fill + caller
  waiver_args, CRM display-only preview render), and the legal evidence columns
  (signer_name, forced-true consent_acknowledged, version pin, rendered_body,
  content_hash, NOT-NULL ip/user_agent, esign_disclosure_version,
  operator_employee_id witness). Load this whenever you touch anything
  waiver-shaped: gym_waivers / gym_waiver_versions / member_waiver_signatures,
  waiver_type / the payer-auth waiver, signing a waiver, rendering
  {{placeholders}}, requires_resign / the re-sign floor, the membership-start
  waiver gate (membership_plans.waiver_ids), the authorize-payer link, the ESIGN
  disclosure, or "why was this member blocked from buying a membership / what
  did they sign".
---

# Waivers Guide

The waiver system is **plain gym config + an append-only legal e-sign log** (no
Stripe). A waiver is a named, versioned document; members sign a SPECIFIC version;
the signed text is preserved for the legal record. Three tables.

## Data model (three tables)

`Database/supabase/schemas/` — schemas are source of truth; the migrations are
`migrations/20260702040000_waiver_signature_legal_hardening.sql` and
`migrations/20260702050000_waiver_type_enum.sql`.

- **`gym_waivers`** — catalog IDENTITY: `waiver_id`, `gym_id`, `name`,
  `current_version_id` (forward FK to versions, declared via `ALTER TABLE` at the
  bottom of the versions schema — circular), `is_deleted` (soft delete),
  **`waiver_type`** (Postgres enum `payer_auth` | `custom`, expandable; mirrored
  as `WaiverType` in `python_data/schema/gym_waiver.py`), timestamps. `custom` =
  a gym-authored document attachable to plans; `payer_auth` = the gym's ONE
  undeletable authorized-payer agreement. `idx_gym_waivers_one_payer_auth` = ≤1
  payer_auth/gym; `trg_protect_payer_auth_waiver` blocks CLIENT roles
  archiving/deleting it and makes `waiver_type` immutable for ALL roles
  (service_role MAY hard-delete during gym-create teardown only). **The trigger
  does NOT protect the API path** (the backend runs at service role) —
  `WaiversDelete.delete_waiver` carries its own payer-auth guard.
- **`gym_waiver_versions`** — conditionally-immutable **TEMPLATE** bodies:
  `version_id`, `waiver_id`, `gym_id`, `version_number` (UNIQUE per waiver),
  `body` (the template — may hold `{{placeholders}}`), `content_hash` (sha256 of
  the template), **`requires_resign`** (BOOLEAN default true), `created_at`.
  `REVOKE UPDATE, DELETE` for clients.
- **`member_waiver_signatures`** — append-only e-sign audit (`REVOKE UPDATE,
  DELETE`): `signature_id`, `gym_id`, `member_id` (the SIGNER), `waiver_id`,
  `waiver_version_id` (the template signed), `signed_at`, `signer_name` (typed),
  `signature_type` enum (`typed` only), `consent_acknowledged` (CHECK = true),
  **`rendered_body`** (NOT NULL — the EXACT agreed text, template with
  `{{placeholders}}` filled in), `content_hash` (sha256 of the **rendered** text),
  `ip_address` INET + `user_agent` VARCHAR (**NOT NULL**),
  **`esign_disclosure_version`** (which ESIGN/UETA disclosure was shown),
  **`operator_employee_id`** (NULLABLE composite FK → `gym_employees` — the staff
  witness who captured an in-person signature). Member sees own; staff see gym's;
  gym staff have an INSERT policy; the backend writes at service_role.

The version is the immutable **template**; the signature freezes the **rendered**
text. `member_authorized_payers.signature_id` FKs a signature as the
authorization's proof (see the authorize-payer link below).

## Versions: edit-in-place vs fork, and the re-sign FLOOR

`WaiversUpdate._maybe_publish_version` (`src/waivers/service/waivers_update.py`):
- A body edit whose hash matches the current version → text untouched (the
  `requires_resign` choice still lands, below).
- Current version has **0 signatures** → **edit in place** (same
  `version_number`), applying `requires_resign` when provided.
- Current version is **signed** → **publish a NEW version** (bump number,
  re-point `current_version_id`), stamped with `requires_resign` (a fork
  defaults to true when omitted). **false** = a minor edit that should NOT
  re-block prior signers.
- **Flag-only update** (`requires_resign` with NO body) → flips the flag on
  the CURRENT version in place (`waiver_versions_update_requires_resign.sql`)
  — the mistake-correction path; moving it moves the floor. The CRM exposes
  this as a "Requires re-sign" switch on the current version's tile.
  `WaiverUpdateData.requires_resign` is `bool | None` — **None (a rename)
  leaves the flag untouched**.

The **re-sign floor** for a waiver = the highest `version_number` among its
versions with `requires_resign = true`. A member is compliant iff they signed a
version `>= floor`. So a `requires_resign=false` minor version does not raise the
floor (prior signatures still count); a `requires_resign=true` material version
raises it (prior signers must re-sign). Version 1 is always `requires_resign=true`
(no one to spare). **Caution:** to fork a NEW version you must sign the current
one first — editing an unsigned current version edits in place (no new row).

## Parametrization ({{placeholders}})

Catalog: `Database/python_data/schema/waiver_parameters.py` (`WAIVER_PARAMETERS`),
mirrored in `CRM/lib/core/constants/waiver_parameters.dart`.
A version `body` may contain `{{key}}` tokens; `WaiversSignatures._render`
substitutes them at sign time. **Backend auto-fills** (in `sign_waiver`):
`{{member_name}}` (the signing member's account name), `{{signer_name}}` (the
typed name), `{{gym_name}}` (⚠ the gyms column is `gym_name`, not `name`),
`{{date}}`. **Callers add extras via `waiver_args`** — the link flow passes
`{{payee_name}}` (the member being paid for). Unknown tokens render literally.
⚠ **The body is markdown, and a markdown serializer may backslash-escape the
token** (`\{\{member\_name\}\}` — displays identically in the editor,
matches nothing; this silently broke ALL rendering in live testing). Both
renderers canonicalize escaped tokens before substituting, and the CRM
editor's save path (`WaiverMarkdownEditor.markdownFromController`) unescapes
tokens so new bodies store clean.
The CRM waiver editor MUST surface the available tokens to the author, always
visible — never behind a collapse (no invisible constants — a required UX
affordance). Jesse chose to store the **full `rendered_body`**, not a params
jsonb. **The CRM sign previews render the placeholders client-side for
display** (`CRM/lib/core/utils/waiver_render.dart`, a display-only mirror of
`_render`: fill known non-empty values, leave the rest literal; `signer_name`
live-updates as the signer types) — the backend render of the stored
`rendered_body` stays authoritative. Both seeded default bodies
(`default_authorized_payer_waiver.md`, `default_liability_waiver.md`) use the
tokens so the feature demos real names.

## The ONE signing path: `sign_waiver`

`WaiversSignatures.sign_waiver` (`src/waivers/service/waivers_signatures.py`),
exposed via the facade `WaiversService.sign_waiver`. It:
1. Resolves the waiver's current version + template body + gym name + the signing
   member's name (`sql/waiver_current_version_for_sign.sql`).
2. **Version-locks**: the client echoes the `waiver_version_id` it displayed; if
   it ≠ the current version → `ValueError("...reload...")` (→ **409**). Archived /
   missing / no-current-version / member-not-in-gym → `"...not found..."` (→ 404).
3. Renders the template with auto args + `waiver_args`; `content_hash` =
   sha256(rendered); inserts via `sql/member_waiver_signatures_insert.sql`.
4. Owns its **own committed transaction**; returns `WaiverSignatureResponse`.

**Standalone endpoint** `POST /api/v1/waivers/{waiver_id}/signatures`
(`waivers_router.py`, staff-only) — request `WaiverSignRequest{gym_id, member_id,
waiver_version_id, signer_name, consent_acknowledged: Literal[True]}`; ip /
user-agent (`src/shared/request_audit.py` sentinels) + operator
(`Auth.get_employee_id`) + esign version are captured **server-side**, never in
the body. This is the general path (e.g. plan liability waivers for the gate).

The 7 other waiver routes are read/admin-CRUD (list, create, update, archive,
versions, roster, by-member status, single get). `WaiverResponse` carries
`waiver_type` so the CRM can discriminate the payer-auth waiver (badge it, hide
Delete/Sign, exclude it from the plan form's waiver selector).
`get_payer_auth_waiver_for_member` + `GET
/api/v1/members/{id}/authorized-payer-waiver` resolve the payer-auth waiver for
display (SQL `waiver_payer_auth_for_member.sql`; seed insert
`waivers_insert_payer_auth.sql`).

**Archive** (`DELETE /` → `WaiversDelete.delete_waiver`): refuses the
payer-auth waiver (service-level guard — the DB trigger only blocks client
roles), and in the same transaction strips the archived waiver's id from every
plan's `waiver_ids` (`sql/membership_plans_strip_waiver_id.sql`) so plans stay
truthful.

**Plans-only-custom guard**: `membership_plans.waiver_ids` is JSONB with no FK,
so plan create/update validate it via
`MembershipPlansBase._validate_waiver_ids`
(`src/plans/sql/membership_plans_waiver_ids_validate.sql`): every id must
exist in the gym, be non-archived, and be `waiver_type='custom'` — the
payer-auth agreement (and any future special-purpose type) is never
plan-attachable. ValueError → 400. The CRM plan form additionally shows only
`custom` waivers in its selector.

## Authorize-payer LINK = one request that REUSES sign_waiver

`PUT /api/v1/members/{member_id}/link` (members_router) → `MemberMembershipsLinked.link_account`
(`src/memberships/service/memberships_linked.py`). Request now
`{payer_member_id, waiver_version_id, signer_name, consent_acknowledged}`. It
resolves the gym's payer-auth waiver (`get_payer_auth_waiver_for_member`) and
calls the **shared `sign_waiver`** to sign it as the payer — rendering the
payer's name (`{{member_name}}`) and the member-being-paid-for
(`{{payee_name}}`, from `member_authorized_payers_link_check.sql`'s candidate
name) — then inserts the `member_authorized_payers` row referencing the new
`signature.signature_id`. **NOT atomic** (signing commits its own txn; the
authz insert is separate) — a retry after a failed insert leaves a harmless
extra append-only signature (by design — Jesse: "complete fine and harmless").
The earlier "needless duplication" was link re-implementing signing; the fix is
link REUSES `sign_waiver`. Operator + ip/ua come from the router
(`Auth.get_employee_id_for_member` + `request_audit`). De-authorization stays the
cascade `remove_authorization` (see `memberships-guide`).

## Membership-START waiver gate

`MemberMembershipsStartValidation._check_waivers`
(`src/memberships/service/memberships_start_validation.py`) +
`sql/member_memberships_start_waivers_check.sql`. For every `(member, plan)` in a
start request, the member must have signed each waiver in `membership_plans.waiver_ids`
at a version `>= the re-sign floor`. **ALL plan types** (one_time/trial/recurring).
Unsigned → `WaiverGateError` (`memberships_exceptions.py`) carrying
`[{member_id, waiver_id, name}]` → the router maps it to **HTTP 422** with
`detail = {message, unsigned}` so the CRM routes the member straight to signing.
Runs in Phase-A validation **before any Stripe call** (nothing written/charged)
and — because validation is shared — also surfaces in the **start preview**. A
no-op for plans with empty `waiver_ids`. **The seed attaches its liability
waiver to EVERY plan — but only AFTER the seed's own membership phase**
(`api_plans.attach_waiver`, called at the end of the per-gym API block in
`python_data/main.py`): attaching earlier would 422 the seed's own starts. The
end state reads as "the gym added a waiver requirement later" — seeded members
show it unsigned, and any NEW start demos the gate + the wizard sign step. No
signatures are seeded (Jesse's pick: minimal).

## Check-in waiver gate

`CheckinMemberGate` (checkin domain) also enforces waivers: a member with an
UNSIGNED required waiver — the union of `waiver_ids` across their CURRENT
(active/frozen) memberships' plans, at the same `requires_resign` floor; the
exact set the member-detail Waivers section shows — gets the
`unsigned_waiver` gate reason (`checkin/sql/checkin_unsigned_waivers.sql`,
`CheckinQueries.get_unsigned_waivers`). `is_member=True` (kiosk/member self)
**rejects** the check-in; staff (`is_member=False`) get the warn-first
pop-up (`requires_confirmation` + the warning, nothing written) and may
record through it with `ignore_warnings` — the standard gate model (see the
`class-system-guide` skill §5). Evaluated for the member NOW (independent of
the occurrence's coverage window). **Reservations/sign-ups are deliberately
NOT waiver-gated** — only the check-in (Jesse: "they can reserve anyways").
The CRM label for the warning is `unsigned_waiver` → "Required waiver not
signed" (`CRM/lib/features/check_in/data/models/check_in_warning.dart`).

## Legal evidence (what a signature proves)

ESIGN/UETA-shaped: intent (`signer_name` + forced-true `consent_acknowledged`),
the exact agreed text (`rendered_body` + its `content_hash`, with
`waiver_version_id` pinning the immutable template), electronic-records consent
(`esign_disclosure_version` → `schema/esign_disclosure.py` /`.md`, placeholder
copy pending legal review), audit trail (`signed_at` UTC, NOT-NULL `ip_address` +
`user_agent`, `operator_employee_id` witness), tamper-evidence (append-only).
Residual: `signer_name` is free-text (no identity verification — standard gym
clickwrap); only `typed` signatures (enum is extensible).

## CRM surface

Reusable `SignWaiverPanel` / `SignWaiverDialog` in `CRM/lib/shared/widgets/`
(a prominent "Signing for <member>" banner — avatar + name + the
member-or-parent/legal-guardian note — then the body read-only via
`WaiverMarkdownEditor`, the ESIGN disclosure, typed name + consent) — used by the authorize-payer dialogs,
the member-detail + editor "Sign" actions, and the purchase wizard. **Every sign
surface pre-renders the `{{placeholders}}` for display** via
`renderWaiverPlaceholders` (`lib/core/utils/waiver_render.dart`): member/payee
names from the dialog's scope, `gym_name` from `selectedGym.displayName`,
`date` = today UTC `YYYY-MM-DD`, and `signer_name` filled LIVE from the typed
name (empty → a `___` blank, escaped so markdown can't read it as a rule). The membership-purchase wizard
(`features/member_details/.../start_memberships/`) has a `signWaivers` step
(after `review`, before `payment`) that blocks until every required waiver is
signed; the backend 422 is the backstop. The member-detail Waivers section
shows the UNION of required + ever-signed waivers (`MemberWaiverStatusRow`:
`required`, `meets_floor`, `waiver_type`, `is_deleted` — signed-below-floor =
the yellow tappable "Needs re-sign" chip; archived/payer-auth rows display
without a sign action) plus a "Sign new waiver" picker over the gym's custom
waivers (any custom waiver is signable, required or not). The waiver editor
surfaces the available `{{placeholders}}` in an ALWAYS-VISIBLE legend; a BODY edit
over a SIGNED version asks at SAVE time via `RequireResignDialog` —
"Don't require re-signing" is the PRIMARY action (small fixes are the common
case), "Require re-signing" the secondary, dismiss aborts the save; the
dialog explains what re-signing does. A rename or an unsigned-version edit
saves silently with the flag untouched (null) — the "Requires re-sign"
switch on the current tile is the deliberate way to set it. The catalog's "N signed" is
`total_signed_count` — DISTINCT members across ALL versions (a re-signer
counts once); `current_version_signed_count` still drives the fork logic. The payer-auth waiver is
badged ("Payer agreement") in the waivers list + editor, its Delete and
standalone "sign member" actions are hidden (signing it outside the link flow
is meaningless — `{{payee_name}}` would render literally), and the plan form's
waiver selector shows `custom` waivers only.

## Conventions / gotchas

- SQL in `.sql` files; **never `:param::type`** — use `CAST(:p AS TYPE)` (the
  bind-hygiene test scans even comments).
- `requires_resign` / `rendered_body` / `esign_disclosure_version` /
  `operator_employee_id` / `waiver_type` are listed user-immutable in
  `python_data/schema/immutable_columns.py`; keep schema + model + diagram +
  `Database/CLAUDE.md` in sync (living docs).
- The hardening migration backfills legacy rows (NULL ip/ua → sentinels;
  `rendered_body` ← the version body) before the NOT NULLs; the enum migration
  backfills `waiver_type='payer_auth'` from the old flag before dropping it.
  The user runs migrations, never you.
- DB-backed waiver tests live in `tests/waivers/` (`test_waiver_sign.py`,
  `test_waivers_versioning.py`, `test_waiver_archive.py` — the payer-auth
  archive guard + plan strip) + `tests/plans/test_plan_waiver_ids_guard.py`
  (the plans-only-custom guard) +
  `tests/memberships/test_start_waiver_gate.py` (the floor logic); the
  `db_writes.authorize_payer` helper drives the real link.
