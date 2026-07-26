---
name: employees-guide
description: >-
  The single source of truth for how CombatDen gym staff (employees) work —
  the verified-email identity model (no user_id, lowercase email matched
  against the JWT), the 4-role capability matrix (owner / admin / front_desk
  / trainer), the `src/employees/` backend CRUD domain (invite_status
  derivation, owner-row protection), soft-archive semantics, the
  `verify_roles` / role-set auth model, the CRM's role_policy /
  route_guard gating, AND the member-facing counterpart surface
  `src/member_portal/` (the only caller of `verify_member_self`).
  Trigger on "employee", "employees", "staff", "role", "member portal",
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
  parent's inbox), which is exactly how a payer sees all their linked members. `Auth.verify_member_self`
  is where that matters: it grants when the caller's email matches the member row's `email`, independent
  of role. Nothing in the CRM uses it — every CRM route is staff-only; it gates the **member portal**
  (`src/member_portal/`, §9), which is why that surface's entry point returns a LIST of member rows and
  every other member route takes an explicit `member_id`.
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
(That reading order is the privilege hierarchy, **not** the Postgres ordinal order: because the migration
appends `front_desk` last, the type is declared `('owner', 'admin', 'trainer', 'front_desk')`, so
`ORDER BY employee_type` sorts owner → admin → trainer → front_desk. Never lean on it for display order —
sort explicitly.)

Two tiers underlie almost every capability (see `CRM/lib/core/auth/role_policy.dart`):
**staff-admin** = owner or admin (full config + management), **staff** = staff-admin OR front_desk
(day-to-day member operations). Trainer sits outside both tiers — read-only.

| Area | Owner | Admin | Front desk | Trainer |
|---|---|---|---|---|
| Dashboard — operational cards (live attendance, overdue payments, upcoming classes) | ✅ | ✅ | ✅ | ❌ |
| Dashboard — overview/income cards (Total Members hero now, gym-income module later) | ✅ | ✅ | ❌ | ❌ |
| Growth / analytics | ✅ | ✅ | ❌ | ❌ |
| Reports & CSV exports (Settings section; `GET /gyms/{id}/reports/report` + `/reports/full-export` zips — `canExportReports`, backend `OWNER_ADMIN`) | ✅ | ✅ | ❌ | ❌ |
| Gym config — VIEW the catalog (plans / discounts / waivers / ranks tabs + rank detail, read-only) | ✅ | ✅ | ✅ | ❌ |
| Gym config — WRITE (create/edit/delete plans·discounts·waivers·ranks, rank enable-toggle, sub-type, reorder, seed preset) | ✅ | ✅ | ❌ | ❌ |
| Member-app theme/showcase — CHANGE the theme (`PUT /gyms/{id}/theme`) | ✅ | ✅ | ❌ | ❌ |
| Gym showcase/theme — READ (`GET /gyms/{id}/showcase`; **also any MEMBER of the gym** — now returns `theme_design_id`) | ✅ | ✅ | ✅ | ✅ |
| Employees tab — manage staff: create / update / archive | ✅ | ✅ | ❌ | ❌ |
| Read the employee roster (`GET /employees/{gym_id}` list — the schedule's instructor picker) | ✅ | ✅ | ✅ | ❌ |
| Gym settings | ✅ | ✅ | ❌ | ❌ |
| Point adjustments | ✅ | ✅ | ❌ | ❌ |
| Rank promotion | ✅ | ✅ | ❌ | ❌ |
| Bulk reprice (plan-wide, `reprice-plan`) | ✅ | ✅ | ❌ | ❌ |
| Single-membership reprice to the plan's ACTIVE price (`PUT /price`) | ✅ | ✅ | ✅ | ❌ |
| Read ongoing / one tracked task (`/tasks/ongoing`, `/tasks/{id}` — in-task badge + poll) | ✅ | ✅ | ✅ | ❌ |
| Plan set-price (mint a new plan price version — a config write) | ✅ | ✅ | ❌ | ❌ |
| Payer-link **remove** | ✅ | ✅ | ❌ | ❌ |
| View members | ✅ | ✅ | ✅ | ❌ |
| Create members (API; CRM "Add Member" UI still deferred — see §6) | ✅ | ✅ | ✅ | ❌ |
| Edit member contact / photo upload | ✅ | ✅ | ✅ | ❌ |
| Member money mgmt (invoices, payment history, card add/update/remove, charge, mark-paid-cash, retry-card, refund, membership start/preview/freeze/unfreeze/cancel/upgrade/cancel-one-time, apply/remove discounts) | ✅ | ✅ | ✅ (full) | ❌ |
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
context below), can **VIEW gym config read-only** (the plans/discounts/waivers/ranks tabs + rank detail)
and the **operational** Dashboard cards, but stays **narrow on config-writes/analytics/staff**. The rule
of thumb: anything that touches "run the front counter for a member who's standing there" — or just
*looking at* how the gym is set up — is front-desk-accessible; anything that **reshapes** gym config
(create/edit/delete/promote/reorder/toggle), or that is staffing, reporting, or gym-income/overview
analytics, is owner/admin-only. **Single-membership reprice to the plan's ACTIVE price (`PUT /price`)
is front-desk-allowed** — it corrects an outdated-price membership onto the current active price (not a
custom amount), so it is member-money work like a charge or a discount; the **plan-wide** bulk reprice
(`reprice-plan`) and a plan's **set-price** (minting a new price version) stay owner/admin. Front desk
also **reads** ongoing tracked tasks (`/tasks/ongoing`, `/tasks/{id}`) so its single reprice never races
a running bulk job, and the employee **roster** (`GET /employees/{gym_id}` list) to fill the schedule's
instructor picker (the Employees TAB itself stays owner/admin). The read/write split is enforced by two capabilities: `canViewCatalog`
(staff, read) vs `canConfigureCatalog` (owner/admin, write); the Dashboard's overview/income cards sit
behind `canViewGymAnalytics` (owner/admin) while `canViewDashboard` itself is staff.

**Trainer** is READ-ONLY: the full schedule and every roster (`ALL_EMPLOYEES`), the gym showcase/theme
read (`GET /gyms/{id}/showcase`, gated by `verify_gym_member_or_employee` — every employee role **AND
any member of the gym** may READ its theme; the response now also carries `theme_design_id` so a
member's app can re-theme), plus their own theme preference — nothing else. A trainer's `landingRoute` is `/schedule` (front desk lands on `/members`; owner/admin land on
`/home`, the dashboard).

### Where this is enforced

- **Backend**: every route names the exact role set it admits (`OWNER_ONLY` / `OWNER_ADMIN` / `STAFF` /
  `ALL_EMPLOYEES` or a custom `frozenset[EmployeeType]`, passed to `Auth.verify_roles` — see §5).
  **The Growth page and the Dashboard's revenue cards ARE backend-gated: `GET /api/v1/growth/` is
  `OWNER_ADMIN` (`growth_router.py`), so front desk can't pull a gym's growth metrics even by calling the
  endpoint directly.** The CRM `growth/` surface is a live bloc/repository feature reading that endpoint,
  and the Dashboard's revenue hero card reads the SAME endpoint — so `canViewGymAnalytics` (owner/admin)
  is a CRM-navigation mirror of a real `OWNER_ADMIN` gate, not a client-only fiction. Front desk's
  OPERATIONAL Dashboard cards (live attendance, overdue payments, upcoming classes) read their own
  `STAFF`-gated endpoints instead — e.g. `GET /api/v1/members/counts` (`STAFF`) — never the growth endpoint.
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
four types) for the trainer-visible reads (full schedule and rosters). The gym showcase/theme read
(`GET /gyms/{id}/showcase`) is a step wider still — gated by `verify_gym_member_or_employee` (every
employee role **OR** any member of the gym; see §2, §6), not `ALL_EMPLOYEES`. Everything else stays
`OWNER_ADMIN` or `STAFF`, which a trainer's `employee_type` never matches.

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

4 endpoints, `EmployeesService` facade. The LIST read is `STAFF`; create / update / archive are
owner/admin-only:

| Route | Gate | What it does |
|---|---|---|
| `GET /api/v1/employees/{gym_id}` | `STAFF` | List all non-archived employees (every type), each with derived `invite_status` — front desk reads the roster to fill the schedule's instructor picker |
| `POST /api/v1/employees/{gym_id}` | `OWNER_ADMIN` | Create a staff member — plain INSERT, no auth-system interaction. `employee_type` may not be `owner` |
| `PUT /api/v1/employees/{gym_id}/{employee_id}` | `OWNER_ADMIN` | Partial update of mutable fields (name/phone/email/pic/description/`employee_type`) |
| `DELETE /api/v1/employees/{gym_id}/{employee_id}` | `OWNER_ADMIN` | Soft-archive (see §4) |

The three WRITES (create / update / archive) guard `auth.verify_roles(gym_id, user_payload,
OWNER_ADMIN)` — front desk and trainer cannot manage staff at all (matches the capability matrix in
§2). The LIST read guards `STAFF`, so front desk can read the roster to fill the schedule's instructor
picker; the Employees **TAB** stays owner/admin, route-gated in the CRM (`canManageStaff`), not by this
endpoint.

**Facade + concerns** (flat in `service/`, `EmployeesBase` holds the shared DB pool + the single-row
fetch/mapper): `EmployeesList` (list/read), `EmployeesCreate` (insert), `EmployeesUpdate` (dynamic partial
UPDATE + owner-row guard), `EmployeesArchive` (soft-archive + owner-row guard). `EmployeesService`
(`employees_service.py`) is a pure one-line-delegation facade over the four.

### `invite_status` — derived, not stored

`EmployeeResponse.invite_status` is an `InviteStatus` enum (`active | pending | none`) computed at **read
time**. The list/get SQL (`employees_list.sql`, `employees_get.sql`) selects a single boolean,
`has_verified_account`, from a scalar `EXISTS` over `auth.users` — **never a JOIN**:

```sql
EXISTS (
    SELECT 1
    FROM auth.users u
    WHERE lower(u.email) = lower(ge.email)
      AND u.email_confirmed_at IS NOT NULL
) AS has_verified_account
```

The `EXISTS` is not a style preference: `auth.users` is unique on email only `WHERE is_sso_user = false`,
so a join could match several rows and fan out — duplicating the employee in the roster (and making the
single-row read non-deterministic in `employees_get.sql`). `EXISTS` cannot fan out. Both `.sql` files
carry that reason as a comment; it is the same rule every identity-resolving query in
`src/shared/sql/` follows.

`EmployeesBase._map_employee` (`service/employees_base.py`) turns that flag into the enum:

- **`none`** — the row has no email (an email-less trainer; instructor data, never a login principal).
- **`pending`** — the row has an email but `has_verified_account` is false (no matching `auth.users` row,
  or one whose `email_confirmed_at IS NULL`).
- **`active`** — `has_verified_account` is true: a confirmed Supabase account exists for that email.

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
- **The owner's email is immutable for now.** `_enforce_owner_rules` also rejects an owner changing
  their OWN email (a no-op same-email update is allowed). Email is the sole identity link (no `user_id`
  FK), so a mistyped owner email would 403 the owner out of their own gym with **no** API recovery — an
  admin cannot edit the owner row, and the owner row cannot be archived. Freezing it removes that
  self-lockout foot-gun. This is a deliberate simplicity **stopgap**; a proper owner-email-change flow
  with re-confirmation is future work (tracked in `TODO.md`).
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
- `verify_gym_member_or_employee(gym_id, user_payload)` — the gym-LEVEL **branding** gate (the
  theme/showcase read). Grants when the caller's verified email matches EITHER a non-archived
  `gym_employees` row at the gym (any `employee_type`) OR any `members` row at the gym (no
  membership-status filter). Takes NO `member_id` and confers no member-scoped access — it only answers
  "does this verified caller belong to this gym in some capacity". It deliberately sits OUTSIDE the
  member-scoped-surface separation (§9): a member reaches it directly with only a `gym_id`, because the
  showcase is gym branding, not member data. Its own `src/shared/sql/auth_gym_member_or_employee.sql`
  carries the same confirmed-account `EXISTS` (drift-guarded). **Only caller:**
  `GET /api/v1/gyms/{id}/showcase`.
- `verify_gym_employee_for_member(member_id, user_payload, staff_roles)` /
  `get_employee_id_for_member(member_id, user_payload, allowed)` — the member-scoped variants: resolve the
  member's gym, then run the gym-scoped check on it. **Staff-only, and they gate EVERY member-scoped route
  in the backend** (reads and writes alike — there is no "or the member themselves" branch anywhere). The
  role-set parameter is **required, with no default**, so a call site can never silently inherit
  `OWNER_ADMIN`.
- `verify_member_self(member_id, user_payload, *, gym_id=None)` — the ONE member-facing gate. The
  caller's verified email must equal the member row's email, a CONFIRMED auth account must exist, and —
  when `gym_id` is given — the member must belong to that gym. **Always pass `gym_id` on a gym-scoped
  route**: without it one email reaches a same-named member at an unrelated gym. 404 unknown member, 403
  otherwise. Its **only** callers are the `member_portal` routes (§9); no CRM route uses it.
- `verify_verified_account(user_payload) -> str` — the standalone primitive for a caller who has no
  `gym_employees` row yet (gym create): 401 with no email claim, 403 on an unconfirmed account, else the
  lowercased email.

**Every one of those queries requires a CONFIRMED auth account**, not just a matching row: each `.sql`
in `FastApiBackend/src/shared/sql/` carries a scalar `EXISTS` over `auth.users` on
`lower(u.email) = <the row's email> AND u.email_confirmed_at IS NOT NULL` (never a JOIN — `auth.users` is
unique on email only `WHERE is_sso_user = false`, so a join can fan out; same reason `employees_list.sql`
uses `EXISTS`). Reading `auth.users` needs the direct pool, so `Auth` is constructed with `db_pool`.
`tests/shared/test_auth_roles.py` holds a drift guard that reads those files off disk.

That DB predicate only means something while GoTrue actually mails confirmations: with
`enable_confirmations` OFF, GoTrue stamps `email_confirmed_at` itself at signup. `AuthSettingsGuard`
(`src/shared/auth_settings_guard.py`, awaited in the `main.py` lifespan) reads GoTrue's published config
at `GET {supabase_url}/auth/v1/settings` and logs a CRITICAL banner when `mailer_autoconfirm` is true —
or refuses to boot when `settings.auth_autoconfirm_policy` is `fail`, which is the **default everywhere**:
`Database/supabase/config.toml` ships `enable_confirmations = true`, so an auto-confirming stack is a
misconfiguration locally just as much as in production. If the guard trips, restart the auth container
rather than re-seeding — GoTrue reads `enable_confirmations` at **container start**, so `supabase db reset`
does not apply it; `supabase stop && supabase start` does.

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
  slash-bounded prefix matching so e.g. `/members` doesn't swallow `/memberships`). The gym catalog is
  split into a **read** gate `canViewCatalog` (staff) and a **write** gate `canConfigureCatalog`
  (owner/admin): `canAccessRoute` tests the catalog **editor** routes (`membershipDetails`,
  `membershipsWaiverEditor`, `membershipsRankEditor`, `membershipsRankPresets`) **before** the broad
  `/memberships*` view prefix — so those need `canConfigureCatalog` while the tabs + the read-only
  `membershipsRankDetail` fall through to `canViewCatalog`, and a front-desk deep-link can't reach an
  editor. Every catalog mutation affordance hides at the widget layer behind
  `selectedGym.role?.canConfigureCatalog`. The Dashboard is gated `canViewDashboard` (staff) for its
  operational cards, with `canViewGymAnalytics` (owner/admin) separately gating its overview/income cards
  (the Total Members hero, a gym-income module later).
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
- **A MobileApp client for the member portal.** The backend surface exists (§9); nothing calls it yet.
- **Member self check-in.** Deliberately NOT built — see §9 for why.
- **Un-archive / restore.** Re-hiring an archived person is a brand-new employee row, not a reactivation
  of the old one (§4). There is no restore endpoint.

---

## 9. The member-facing surface — `src/member_portal/`

The staff model above has an exact counterpart for the person on the other side of the counter. It is
a **separate domain and a separate router** (`/api/v1/member/...`), NOT a "or the member themselves"
branch inside a staff route — that branch existed once, let a member self-check-in while overriding
every gate (the unsigned-waiver legal gate included) and cancel their own memberships, and was deleted.
Keeping the two surfaces physically separate is what makes it structurally impossible to reintroduce.

**What admits a member.** `Auth.verify_member_self(member_id, user_payload, *, gym_id=...)` — the same
verified-email identity rule as staff, applied to `members.email` instead of `gym_employees.email`:
the lowercased JWT claim must equal the member row's email, a CONFIRMED `auth.users` account must exist
for it, and the member row must belong to the PATH gym. No `employee_type` is involved; a member holds
no role and gets nothing from `verify_roles`. Symmetrically, **staff get nothing from
`verify_member_self`** — an owner cannot read a member's portal routes, they use the CRM routes.

**Three invariants** (they are the whole point of the domain):

1. **`member_id` is never derived from the JWT.** `GET /api/v1/member/members` (gated by
   `verify_verified_account`, since no member is named yet) resolves the caller's email to their member
   rows **across gyms** — a LIST, because `members.email` is deliberately non-unique (§1, the family
   case). Every other route takes the chosen `member_id` + `gym_id` explicitly. Each row also carries
   its gym's display block **and its three CAPABILITY flags** — `gym_rank_enabled` (the stored
   `gyms.is_rank_enabled` toggle) plus `gym_has_rewards` / `gym_has_videos`, both DERIVED from data
   (there is no toggle for either) by mirroring the exact predicate of the member-facing read behind
   each tab. The app picks its bottom-nav tabs from them, so they must be right at first paint and
   survive offline — which is why they ride the once-per-boot, cached identity read rather than the
   profile. Detail (including the served-feed drift guard) lives in `FastApiBackend/CLAUDE.md` under
   *Member portal domain*.
2. **Every gym-scoped route passes `gym_id`** to the gate, so a member row at an unrelated gym is a 403
   rather than a served page.
3. **No client-selectable gate semantics.** `is_member`, `ignore_warnings`, `auto_approve`, `rejected`,
   `include_inactive` appear in **no** member-facing schema or query param; the strict path is hardwired
   server-side. This is the direct lesson of the deleted branch: a caller must never choose the gate
   they are judged by.

**What it admits** (14 routes, all thin delegation to the SAME services the CRM uses): the caller's
member rows; their own profile (rank progress, points balance, streak — including
`retention.current_week_attended_weekdays`, THIS week's attended weekdays as SUNDAY-FIRST indices over
the streak's own gym-local week, so a rank-disabled gym renders its week strip from the same call —
membership cards, recent + pending redemptions; a projection of `MembersBillingDetailService`); their
streak and class history;
their gym's **schedule board**; their own **reservations** (`POST`/`DELETE .../signup`); their gym's
**active** reward catalog and a **pending** redemption with their own points; and their personalized
**video** feed / rotating rec / rec click.

**Plus one gym-LEVEL read that is NOT a `member_portal` route.** A member also reads their gym's
branding via `GET /api/v1/gyms/{id}/showcase` (the **theme** domain, not `/api/v1/member/...`), so the
app can re-theme itself to the gym — the response carries `theme_design_id`. That route is gated by
`verify_gym_member_or_employee` (any employee role OR any member of the gym; §2, §6), NOT
`verify_member_self`: it takes only a `gym_id` and returns gym branding, not member data, so it
deliberately lives outside this domain's member-scoped separation. It is the mobile app's one call that
isn't under the member router.

**What it refuses, deliberately:**

- **Self check-in.** A reservation is not attendance — `member_attendance` is still only written by a
  staff check-in. Self check-in would bypass the front desk and the unsigned-waiver legal gate, and the
  strict kiosk gate silently *skips* rather than errors, which reads as a broken button to a member.
  Reserve a spot, then a human checks you in.
- Cancelling or unlinking a membership or card, editing their own email (it is their identity anchor),
  any invoice/payment mutation, points adjustment, self-approving a redemption, and anything staff-only.

Deep detail (the route/gate table, the cross-gym reward guard on redeem) lives in
`FastApiBackend/CLAUDE.md` under *Member portal domain*.

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
- **Member portal:** `FastApiBackend/src/member_portal/` — `member_portal_router.py`,
  `schema/member_portal_schema.py`, `service/member_portal_service.py`,
  `sql/member_portal_list_members.sql`. Tests:
  `FastApiBackend/tests/member_portal/test_member_portal_router.py` (router units),
  `test_member_portal_capabilities_db.py` (the live derivation + served-feed drift guard),
  `test_member_portal_week_strip_db.py` (the gym-local Sunday-first week strip) and
  `FastApiBackend/tests/integration/test_member_portal_integration.py` (the live gate proof).
- **CRM:** `CRM/lib/core/auth/employee_role.dart`, `role_policy.dart`, `CRM/lib/core/navigation/
  route_guard.dart`, `CRM/lib/core/errors/exceptions.dart` (`ForbiddenException`),
  `CRM/lib/features/login/presentation/widgets/register_form.dart` (email-confirmation signup).

---

## This is a living document

This skill is the single source of truth for how the employees/roles system works. Whenever the model
genuinely changes — a new role, a capability moving between roles, a new endpoint, an invite-email flow
landing, un-archive getting built — **update this skill in the same change** so it never goes stale.
