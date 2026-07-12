---
name: employees-guide
description: >-
  The single source of truth for how CombatDen gym staff (employees) work —
  the verified-email identity model (no user_id, lowercase email matched
  against the JWT), the 4-role capability matrix (owner / admin / front_desk
  / trainer), the `src/employees/` backend CRUD domain (invite_status
  derivation, owner-row protection), soft-archive semantics, the
  `verify_roles` / role-set auth model, and the CRM's role_policy /
  route_guard gating. Trigger on "employee", "employees", "staff", "role",
  "front desk", "trainer", "invite", "access", "employee_type",
  "archive employee", "who can do what", or any change to `gym_employees`,
  `src/employees/`, `src/shared/auth.py`, or the CRM's
  `lib/core/auth/`.
---

# Employees — identity, roles, and access

This is the deep domain knowledge for CombatDen's gym-staff (employee) system: who can log in, what
each role can do, and how access is enforced end to end. CLAUDE.md files hold only "how to work here"
pointers to this skill. When the model changes — a new role, a capability moving between roles, a new
endpoint, an archive/re-hire flow — **update this skill in the same change** (it is a living document —
see the bottom).

---

## 1. Identity = verified email, not an auth-user id

There is **no `user_id` FK anywhere in this system**. Both `gym_employees` and `members` dropped their
`auth.users` FK columns. Access is a **join on email**, evaluated fresh on every request:

- A person's Supabase JWT carries an `email` claim. The backend lowercases it and matches it against a
  row's stored `email` column (stored emails are lowercase-normalized at write time, so the match is an
  exact `.eq`).
- **`gym_employees.email`** — a verified Supabase `auth.users` account whose (lowercased) email matches
  a non-archived `gym_employees` row is that person's login, at that row's `employee_type`. The Postgres
  RLS helpers (`is_gym_employee`, `is_gym_admin_or_owner` in `Database/supabase/schemas/gyms.sql`) do the
  same email join via `auth.jwt() ->> 'email'`; the FastAPI layer's `Auth._resolve_employee`
  (`FastApiBackend/src/shared/auth.py`) does it again over the decoded JWT payload. Two independent
  enforcement points, same identity rule.
- **`gym_employees` has a partial unique index** — `unique_employee_email_gym` on `(gym_id, lower(email))
  WHERE email IS NOT NULL` — one employee row per email per gym. A duplicate create trips it and surfaces
  as `DuplicateEmployeeError` → 409.
- **`members.email` has NO uniqueness constraint, by design** — families share an email. A parent's
  verified account matches **every** member row bearing their email (siblings, multiple kids under one
  parent's inbox), which is exactly how a payer sees all their linked members. `verify_can_view_member`
  (`Auth`) grants access when the caller's email matches the member's `email`, independent of role.
- **Multi-gym is native.** Because access is just "does a non-archived row at this gym match my email,"
  the same person can hold rows (even different roles) at multiple gyms; `GET /api/v1/gyms/` returns
  every gym whose non-archived employee row matches the caller's verified email, each annotated with the
  role at that gym.
- **`chk_principal_has_email`** (CHECK on `gym_employees`): `employee_type = 'trainer' OR email IS NOT
  NULL`. Only a `trainer` row may be email-less — that's instructor **data** (a name/photo shown on
  classes), never a login principal. Every login-carrying role (owner, admin, front_desk) must carry an
  email. This constraint **replaced** the old `chk_trainer_has_no_account` rule from when trainers could
  not log in at all (see §3).
- **Archived = no access, ever.** `gym_employees.archived_at` (nullable timestamptz) is the soft-archive
  flag. Every authorization query — the RLS helpers, `Auth._resolve_employee`, `Auth.verify_staff_principal`
  — filters `archived_at IS NULL`. An archived row's email loses access instantly, with **zero** touch to
  the underlying Supabase auth account (see §4).

---

## 2. The 4-role capability matrix

`employee_type` enum: `owner | admin | front_desk | trainer` (`Database/supabase/schemas/gyms.sql`,
mirrored as `EmployeeType` in `Database/python_data/schema/gym_employee.py`). `front_desk` is the newest
value — added specifically to give day-to-day counter staff a scoped account without owner/admin power.

Two tiers underlie almost every capability (see `CRM/lib/core/auth/role_policy.dart`):
**staff-admin** = owner or admin (full config + management), **staff** = staff-admin OR front_desk
(day-to-day member operations). Trainer sits outside both tiers — read-only.

| Area | Owner | Admin | Front desk | Trainer |
|---|---|---|---|---|
| Dashboard / KPIs | ✅ | ✅ | ❌ | ❌ |
| Growth / analytics | ✅ | ✅ | ❌ | ❌ |
| Gym config (plans, discounts, waivers, ranks admin) | ✅ | ✅ | ❌ | ❌ |
| Member-app management (theme, showcase) | ✅ | ✅ | ❌ | ❌ |
| Employees tab (manage staff) | ✅ | ✅ | ❌ | ❌ |
| Gym settings | ✅ | ✅ | ❌ | ❌ |
| Point adjustments | ✅ | ✅ | ❌ | ❌ |
| Rank promotion | ✅ | ✅ | ❌ | ❌ |
| Bulk reprice (plan-wide) | ✅ | ✅ | ❌ | ❌ |
| Custom single-membership price / set price | ✅ | ✅ | ❌ | ❌ |
| Payer-link **remove** | ✅ | ✅ | ❌ | ❌ |
| View members | ✅ | ✅ | ✅ | ❌ |
| Create members (API; CRM "Add Member" UI still deferred — see §6) | ✅ | ✅ | ✅ | ❌ |
| Edit member contact / photo upload | ✅ | ✅ | ✅ | ❌ |
| Member money mgmt (invoices, payment history, card add/update/remove, charge, mark-paid-cash, refund, membership start/preview/freeze/unfreeze/cancel/upgrade/cancel-one-time, apply/remove discounts) | ✅ | ✅ | ✅ (full) | ❌ |
| Rewards redeem + approve/reject | ✅ | ✅ | ✅ | ❌ |
| Reward point-value adjustments | ✅ | ✅ | ❌ | ❌ |
| Check-ins (single/batch/undo, signups, rosters, history) | ✅ | ✅ | ✅ | ❌ (read rosters only) |
| Classes — read | ✅ | ✅ | ✅ | ✅ |
| Classes — cancel/reschedule a SINGLE occurrence | ✅ | ✅ | ✅ | ❌ |
| Classes — templates/ranges/capacity/instructor edits | ✅ | ✅ | ❌ | ❌ |
| Full schedule (all classes, all rosters) — read | ✅ | ✅ | ✅ | ✅ |
| Waivers — read + sign | ✅ | ✅ | ✅ | ❌ |
| Payer-link **create** / check | ✅ | ✅ | ✅ | ❌ |
| Own CRM theme (light/dark/system) preference | ✅ | ✅ | ✅ | ✅ |
| Delete gym | ✅ | ❌ | ❌ | ❌ |

**Front desk is deliberately wide on member/money operations** (this was the final, expanded scope — see
context below) and **narrow on config/analytics/staff**. The rule of thumb: anything that touches "run
the front counter for a member who's standing there" is front-desk-accessible; anything that reshapes gym
config, staffing, or reporting is owner/admin-only.

**Trainer** is READ-ONLY: the full schedule and every roster, plus their own theme preference — nothing
else. A trainer's `landingRoute` is `/schedule` (front desk lands on `/members`; owner/admin land on
`/home`, the dashboard).

### Where this is enforced

- **Backend**: every route names the exact role set it admits (`OWNER_ONLY` / `OWNER_ADMIN` / `STAFF` /
  `ALL_EMPLOYEES` or a custom `frozenset[EmployeeType]`, passed to `Auth.verify_roles` — see §5).
- **CRM**: `RolePolicy` extension on `EmployeeRole` (`CRM/lib/core/auth/role_policy.dart`) exposes one
  boolean getter per capability (`canManageStaff`, `canViewDashboard`, `canCreateMembers`, …), each keyed
  to a tier. Nav, route access, and section visibility all read these getters — **nothing hard-codes a
  role comparison** outside this one file. `EmployeeRole.unknown` (a forward-compat fallback for an
  unrecognized backend value) falls through both tiers, landing on trainer-level (least-privilege) access.

---

## 3. Trainers can log in now (the reversal)

Historically trainers had **no accounts at all** — `gym_employees` enforced a `chk_trainer_has_no_account`
constraint that forbade a trainer row from carrying an email. That rule is **gone**. Trainers now log in
like any other employee type; the DB constraint flipped from "trainer must have no email" to
`chk_principal_has_email` — "every **login-carrying** role must have an email; only trainer may skip it."

Access for a trainer is still role-set-gated per route exactly like every other role — **not** a blanket
owner/admin cut with everyone else lumped together. `src/shared/auth.py` exports `ALL_EMPLOYEES` (all
four types) for the trainer-visible reads (full schedule, rosters); everything else stays `OWNER_ADMIN` or
`STAFF`, which a trainer's `employee_type` never matches.

---

## 4. Archive semantics — soft-delete only, auth accounts never touched

`DELETE /api/v1/employees/{gym_id}/{employee_id}` **archives**, never hard-deletes:

- Sets `gym_employees.archived_at = now()`. The row itself is permanent — instructor references (a
  trainer shown on a class) and waiver-operator references (`member_waiver_signatures.operator_employee_id`)
  are FKs into `gym_employees`, so a hard delete would orphan history. Hard delete is **structurally
  impossible** given those FKs, not just a policy choice.
- **No Supabase auth account is ever touched.** Archiving doesn't disable, delete, or sign out the
  person's Supabase login — it just stops matching. Access dies because **every** authorization check
  (the RLS helpers, `Auth._resolve_employee`, `Auth.verify_staff_principal`) filters `archived_at IS NULL`,
  so an archived row simply never matches again. If the same email is later added back as a fresh row at
  the same or another gym, that new row grants access again immediately — no re-verification needed
  (the Supabase account was never touched in the first place).
- **The owner row can never be archived.** `EmployeesArchive.archive_employee` catches the no-op archive,
  re-reads the target, and raises `OwnerRowProtectedError` (→ 403) if it's the owner.
- **Un-archive / restore is NOT built.** Re-hiring an archived person means creating a brand-new employee
  row (a new `employee_id`); there is no "undo archive" endpoint. See §6.

---

## 5. Backend domain — `src/employees/`

4 endpoints, `EmployeesService` facade, all owner/admin-only:

| Route | What it does |
|---|---|
| `GET /api/v1/employees/{gym_id}` | List all non-archived employees (every type), each with derived `invite_status` |
| `POST /api/v1/employees/{gym_id}` | Create a staff member — plain INSERT, no auth-system interaction. `employee_type` may not be `owner` |
| `PUT /api/v1/employees/{gym_id}/{employee_id}` | Partial update of mutable fields (name/phone/email/pic/description/`employee_type`) |
| `DELETE /api/v1/employees/{gym_id}/{employee_id}` | Soft-archive (see §4) |

All four guard `auth.verify_roles(gym_id, user_payload, OWNER_ADMIN)` — front desk and trainer cannot
manage staff at all (matches the capability matrix in §2).

**Facade + concerns** (flat in `service/`, `EmployeesBase` holds the shared DB pool + the single-row
fetch/mapper): `EmployeesList` (list/read), `EmployeesCreate` (insert), `EmployeesUpdate` (dynamic partial
UPDATE + owner-row guard), `EmployeesArchive` (soft-archive + owner-row guard). `EmployeesService`
(`employees_service.py`) is a pure one-line-delegation facade over the four.

### `invite_status` — derived, not stored

`EmployeeResponse.invite_status` is an `InviteStatus` enum (`active | pending | none`) computed at **read
time** from a `LEFT JOIN auth.users` in the list/get SQL (`employees_list.sql`, `employees_get.sql`):

```sql
LEFT JOIN auth.users u ON lower(u.email) = ge.email
```

- **`none`** — the row has no email (an email-less trainer; instructor data, never a login principal).
- **`pending`** — the row has an email but no matching `auth.users` row has confirmed it
  (`u.email_confirmed_at IS NULL` or no matching row at all).
- **`active`** — a verified Supabase account exists for that email (`u.email_confirmed_at IS NOT NULL`).

There is no stored invite/status column and no invite-token flow — `invite_status` is purely a read-time
reflection of "does a verified auth account currently exist for this email." Sending an actual
notification/invite email is deferred (see §6).

### Owner-row rules

- The owner row is **seeded at gym creation**, one per gym, and can never be created via
  `POST /employees/{gym_id}` (`employee_type: owner` is rejected by the Pydantic validator on both create
  and update requests).
- **Only the owner may edit their own row**, and their `employee_type` can never change — enforced in
  `EmployeesUpdate._enforce_owner_rules`: if the update target is the owner row, the caller's own
  `employee_id` must equal the target's AND the request must not attempt an `employee_type` change,
  or it raises `OwnerRowProtectedError` (→ 403).
- **The owner row can never be archived** (§4).

---

## 6. The auth role-set model

`FastApiBackend/src/shared/auth.py` is the single enforcement point for every per-gym / per-member check.
Role sets are `frozenset[EmployeeType]` constants, and every route names exactly which set it admits:

```python
OWNER_ONLY   = frozenset({EmployeeType.owner})
OWNER_ADMIN  = frozenset({EmployeeType.owner, EmployeeType.admin})
STAFF        = frozenset({EmployeeType.owner, EmployeeType.admin, EmployeeType.front_desk})
ALL_EMPLOYEES = frozenset(EmployeeType)  # includes trainer
```

The core check is `Auth.verify_roles(gym_id, user_payload, allowed)` — resolves the caller's verified
email against a non-archived `gym_employees` row at `gym_id` whose `employee_type ∈ allowed`; 401 if the
JWT carries no `email` claim, 403 if no matching row exists. Everything else is a thin wrapper or variant
over the same `_resolve_employee` query:

- `get_employee_id(gym_id, user_payload, allowed=OWNER_ADMIN)` — same check, returns the `employee_id`
  (used to stamp an operator/witness on a record, e.g. a waiver signature).
- `verify_staff_principal(user_payload, allowed=OWNER_ADMIN)` — the gym-**agnostic** staff gate (matches
  at *any* gym); used by endpoints with no `gym_id` (the shared image-upload proxy).
- `verify_gym_owner` / `verify_gym_admin_or_owner` — thin wrappers over `verify_roles` with `OWNER_ONLY` /
  `OWNER_ADMIN` (the latter mirrors the DB's `is_gym_admin_or_owner` RLS function at the API layer).
- `verify_can_view_member(member_id, user_payload, staff_roles=OWNER_ADMIN)` — grants access when the
  caller IS the member (email match, covering the family case) **OR** holds one of `staff_roles` at the
  member's gym.
- `verify_gym_employee_for_member` / `get_employee_id_for_member` — the staff-**only** (never the member
  themselves) member-scoped variants, for ops a member must not self-serve (e.g. authorizing a payer).

A route documents which roles it admits by which constant it passes — e.g. a trainer-visible schedule read
passes `ALL_EMPLOYEES`; a money-moving membership op passes `STAFF`; gym-config writes and the employees
domain itself pass `OWNER_ADMIN`; Stripe Connect onboarding passes `OWNER_ONLY` via `verify_gym_owner`.

---

## 7. CRM — role_policy, route_guard, nav gating

- **`lib/core/auth/employee_role.dart`** — `EmployeeRole` enum (`owner | admin | frontDesk | trainer |
  unknown`), JSON-parsed with a safe `unknown` fallback (per the CRM's resilient-enum-parsing convention).
- **`lib/core/auth/role_policy.dart`** — the `RolePolicy` extension on `EmployeeRole`: one boolean getter
  per capability (see §2's table), plus `landingRoute` (where a role lands after gym activation, and where
  a denied route redirects) and `canAccessRoute(path)` (the route-level gate, checked with
  slash-bounded prefix matching so e.g. `/members` doesn't swallow `/memberships`).
- **`lib/core/navigation/route_guard.dart`** — `redirectRouteFor(path, role)`, a pure function wrapping
  `role.canAccessRoute`; returns the role's `landingRoute` to redirect to on a denied path, or `null` to
  allow. Shared by `main.dart`'s `_onGenerateRoute` and the auth gate's initial-route resolution.
- **Nav filtering** — the nav rail/menu calls a `visibleNavSections(role)` helper (built on the same
  `RolePolicy` getters) so a role never even sees a nav entry it can't open.
- **`ForbiddenException`** (`lib/core/errors/exceptions.dart`) — thrown/caught on a backend 403, shown as
  a role-specific "you don't have permission" message rather than the generic server-error copy.

### Signup uses Supabase email confirmation

Employee signup no longer auto-activates on submit. `register_form.dart` (the login feature) drives a
Supabase signup that requires **email confirmation** before the account is usable: the UI has a dedicated
"verify your email" register state, and a confirmation-link click auto-logs the person in once Supabase
marks the address confirmed. This is the mechanism `invite_status` reads (§5) — a freshly-created employee
row stays `pending` until the person completes this confirmation flow, then flips to `active`.

---

## 8. Deferred — not built yet

Recorded so a future read of this skill doesn't assume these exist:

- **Notification / invite email + resend.** Creating an employee row does not send the person anything —
  no email, no magic link, no "you've been invited" notice. They must separately sign up with the matching
  email through the normal Supabase signup flow (§7) to activate. There's no resend-invite affordance
  either.
- **The Add-New-Member CRM UI bridge.** Front desk (and owner/admin) can create members via the backend
  API (`POST /members`, §2), but the CRM's "Add Member" button is still a stub (see `TODO.md`) — the UI
  flow that would call this endpoint hasn't been wired.
- **Kiosk mode.** No kiosk UI exists in CRM or MobileApp yet; front-desk/trainer distinctions for a kiosk
  flow are not applicable until it's built.
- **Un-archive / restore.** Re-hiring an archived person is a brand-new employee row, not a reactivation
  of the old one (§4). There is no restore endpoint.

---

## Key files

- **Schema:** `Database/supabase/schemas/gyms.sql` (`gym_employees` table, `employee_type` enum,
  `chk_principal_has_email`, `unique_employee_email_gym`, the `is_gym_employee` /
  `is_gym_admin_or_owner` / `gym_has_owner` security-definer RLS helpers), `access_rules/gyms.sql` (RLS
  policies), `Database/supabase/schemas/members.sql` (`members.email`, no uniqueness).
- **Models/enums:** `Database/python_data/schema/gym_employee.py` (`EmployeeType`, `ThemeMode`).
- **Backend domain:** `FastApiBackend/src/employees/` — `employees_router.py`, `schema/employees_schema.py`
  (`InviteStatus`, `EmployeeCreateRequest`, `EmployeeUpdateData`/`Request`, `EmployeeResponse`),
  `service/` (`employees_base.py`, `employees_list.py`, `employees_create.py`, `employees_update.py`,
  `employees_archive.py`, `employees_service.py`), `sql/` (`employees_get.sql`, `employees_list.sql`,
  `employees_insert.sql`, `employees_update.sql`, `employees_archive.sql`), `employees_exceptions.py`
  (`EmployeeNotFoundError`, `DuplicateEmployeeError`, `OwnerRowProtectedError`).
- **Auth:** `FastApiBackend/src/shared/auth.py` — the `Auth` class, role-set constants, `verify_roles` and
  every variant.
- **CRM:** `CRM/lib/core/auth/employee_role.dart`, `role_policy.dart`, `CRM/lib/core/navigation/
  route_guard.dart`, `CRM/lib/core/errors/exceptions.dart` (`ForbiddenException`),
  `CRM/lib/features/login/presentation/widgets/register_form.dart` (email-confirmation signup).

---

## This is a living document

This skill is the single source of truth for how the employees/roles system works. Whenever the model
genuinely changes — a new role, a capability moving between roles, a new endpoint, an invite-email flow
landing, un-archive getting built — **update this skill in the same change** so it never goes stale.
