# Branch Comparison — `origin/old_full_crm` vs `restore_crm` (working tree)

**Scope:** CRM (Flutter) · FastApiBackend · Database
**Baseline:** OLD = `origin/old_full_crm` (HEAD `3596026`). CURRENT = the live **working tree** of `restore_crm` (the in-progress restore — staged + untracked, *not* yet committed).
**Depth:** full dead-code / reachability trace (grep-verified).
**Method:** 12-agent read-only workflow + 4 hand-verified spot-checks.

> Analysis only — generating this document changed no code. The "next actions" at the end are optional.

---

## 0. The single most important framing fact

`origin/old_full_crm` is a **direct ancestor** of `restore_crm` — it *is* the merge-base. The current branch = OLD + **121 commits** that (a) deleted `FlutterCRM` + the whole Stripe billing backend, (b) replaced it with a demo admin app (`AppManagement`) and a payment-free engagement model, and (c) added entirely new systems (ThemeService, VideoService). The **restore work** then re-adds the billing backend on top — and **almost all of it is uncommitted** (staged or `??` untracked). The committed tip of `restore_crm` does *not* contain the restore; the working tree does. Everything below compares OLD against that working tree.

Identity rename runs through everything restored: `crm_user_id → member_id`, table family `user_gym_* → member_*`, and the `gyms_unfiltered`/view split collapsed to a plain `gyms` table. This re-key is **complete** — zero residual `crm_user_id` or `user_gym_profiles` references anywhere in restored schemas, SQL, Python, or Dart.

---

## 1. TL;DR

- **The CRM restore is ~90% there and faithful.** Billing schema, RLS, FastAPI billing domains, and the Flutter logic+UI layers are all restored and correctly re-keyed. The member-detail billing surface (16 of ~18 action dialogs) is rebuilt natively in the new design.
- **Net new capability** the old branch never had: **ranks** (engagement ladder), **rewards** (points store), **class attendance/streaks** (redesigned), **VideoService** content tables, **multi-gym** support, a **public no-auth theme browser**, and a real **dashboard**.
- **Three real problems worth attention** (all verified):
  1. 🔴 **Security:** the 4 `member_*` billing tables are missing the `hide_incomplete_stripe_records` restrictive RLS policy that `Database/CLAUDE.md` line 24 *mandates*. Partially-synced billing rows are visible to authenticated clients. Doc says one thing, SQL does another.
  2. 🟠 **Refund 404:** the Flutter CRM calls `POST /members/{id}/refund`, which has **no backend route**. Self-documented, part of the intentional "unfinished 25%," but it will 404 if triggered.
  3. 🟠 **Invoice child tables never written:** `member_invoice_line_items` and `member_invoice_applied_discounts` have a read path but **no `INSERT` anywhere** — the invoice-paid webhook only writes `member_invoices`/`member_charges`. They will always be empty.
- **Large backend surface is built but unwired to the CRM UI:** all of `ranks/*` (10 endpoints), all of `rewards/*` (6), `membership_plans` mutations (7), `discounts` mutations (3), `classes/checkin` + `classes/streak`, and `PUT /gyms/{id}` — fully implemented, zero Flutter callers.
- **Old branch features deliberately left behind:** the entire cycle-counts system, the plan-eligibility check-in flow, FlutterCRM's whole dark/orange design system + presentation layer, the `gym_class_schedules`/`exceptions`/`log` tables, and `user_*` schema/generator modules. All intentional per `CRM_RESTORE.md`.
- **Silent drops worth a glance:** the `'disabled'` gym onboarding status value, `PersonalInfo.waiver_id`, `FastApiBackend/src/gyms/notes/` (7 docs), and the members-list **advanced filter** (status multiselect + date range) — none documented as intentional.

---

## 2. Features ADDED (present in this branch, absent in old)

### Database
| Added | What |
|---|---|
| `gym_ranks`, `rank_presets` | Per-gym rank ladder + global preset templates (`bjj`/`mma`/`generic`). New `gym_type` enum. `members.current_rank_id` FK; `gyms.is_rank_enabled`. |
| `member_attendance` | Append-only check-in log (`member_id` × `class_history_id`, idempotent). |
| `class_history` | Append-only record of class instances that occurred (decoupled from billing). |
| `class_instance_exceptions`, `class_range_exceptions` | Single-date and date-range schedule overrides (replace old `gym_class_exceptions`). |
| 7× `video_*` tables | VideoService content (pool, demo gyms, feeds, classes, queries, rewards, cost log). **Out of CRM scope** — separate system. |
| `gyms` Stripe Connect cols | `stripe_account_id TEXT UNIQUE`, `stripe_onboarding_status` (+ named CHECK). `employee_type` promoted VARCHAR→enum. |
| `members` unified table | Identity **+** billing columns in one table; `member_billing_profile` survives only as a filtered **VIEW** (`WHERE stripe_customer_id IS NOT NULL`). Supersedes the planned companion table. |
| `gym_classes` schedule fold-in | 15 schedule columns + `image_url` + `points_worth` absorbed; `recurring_unit` enum; dropped `allowed_plan_ids`. |

### FastAPI
| Added | What |
|---|---|
| `ranks/` domain | 10 endpoints (list/create/from-preset/presets/grouped/enabled toggle/CRUD). Fully wired in `main.py` + DI. |
| `rewards/` domain | 6 endpoints (CRUD + atomic `redeem` + redemption history). Two services. Fully wired. |
| `classes/streak` + redesigned `checkin` | Idempotent attendance model over `member_attendance`+`class_history`; simple `CheckinRequest/Response`. |
| `members` spine merge | New `MembersBillingDetailService`, `/list`, `/counts`, `GET /{member_id}` + `GET /{member_id}/billing`, `BillingRank` in detail. |
| `gyms` multi-gym + Connect | `GET /gyms/` (list w/ role), `PUT /gyms/{id}`, `/{gym_id}/onboarding[/link]` (re-keyed off `/me`). User may own multiple gyms (`GymAlreadyExistsError` removed). |
| Config / tests | Stripe Connect env vars, expanded CORS (app/themes domains), `email-validator` dep, stripe floor bump, new `tests/integration/` package + 7 unit/router tests + `seed_constants.py`. |

### Flutter (CRM)
| Added | What |
|---|---|
| 6 new feature trees | `employees`, `growth`, `qr_codes`, `schedule`, `theme_browser`, and `members` (the member-app configurator: Theme/Videos/Loyalty tabs). |
| `showcase/` module | 7 phone-frame preview screens, live-re-themed via `theme_flutter`, for the live theme tab. |
| Dual entrypoints | `main.dart` (auth admin) + `main_theme_browser.dart` (public no-auth, `themes.combatden.net`). |
| Real dashboard | `home/` went from a routing stub to a dashboard with a **live** overdue-payments bloc + mock hero/attendance/upcoming cards. |
| Navigation | `core/navigation/app_routes.dart` + `url_sync.dart` (deep-linking), `core/state/selected_gym.dart` (gym/videoGym id spaces). |
| Auth gate + gym picker | `auth_gate.dart` resolves 0/1/2+ gyms → setup / workspace / picker. `gym_picker_screen.dart` new. |
| Native billing rebuild | `member_details/presentation/sections/` (13 sections) + dialogs rebuilt in the light/blue AppManagement design. |
| Dev auto-login | `LoginBloc` dart-define-gated auto-login (supports the qa-crm skill). |

> Backend connectivity of the new Flutter features: **live** = home/overdue (FastAPI), members list/detail (FastAPI), schedule board + Videos tab + theme preview (VideoService/ThemeService). **mock only** = employees, growth, qr_codes, loyalty tab, schedule *form* (save wired to nothing), video-agent editor.

---

## 3. Features LEFT BEHIND in the old branch (in old, not in this branch)

### Intentional (documented in `CRM_RESTORE.md`)
- **Cycle-counts system (FastAPI):** `ClassesCycleCountsService`, `classes_cycle_counts_schema.py`, `classes_all_memberships.sql`, the member-detail cycle-counts bridge. Per-membership "classes used/remaining per cycle" is gone from the detail screen. (`CRM_RESTORE.md` flags this as net-new work, not restored.)
- **Plan-eligibility check-in flow (FastAPI):** old `checkin` did plan selection, eligibility gating, auto-end-membership; replaced by a plain idempotent attendance insert. `class_plan_eligibility.sql`, `classes_checkin_end_membership.sql`, `ClassesCheckinRequest` membership breakdown — all dropped.
- **Class scheduling tables (DB):** `gym_class_schedules` (folded into `gym_classes`), `gym_class_exceptions` (→ instance/range), `gym_classes_log` (→ `class_history` + `member_attendance`). Note: old log's `plan_id`/`item_id` billing linkage is **not** carried forward.
- **FlutterCRM design + presentation layer:** entire `presentation/` for all 5 old features, `design_constants.dart` (orange/dark), `app_theme.dart` (dark), `app_shell.dart`, `home_screen.dart` routing stub, all `shared/widgets/`. AppManagement's design wins by design.
- **`user_*` schema + generator modules (DB python_data):** `user_gym_profile.py`, `user_activity.py`, `user_gym_reward_redemption.py`, `user_gym_charge/invoice*.py`, generators `profiles/discounts/plans/prices/reward_redemptions.py` (Stripe seeding now goes through `api_creation/` against the live backend).
- **Endpoints renamed, not lost:** `crm_members_list → /list`, `crm_total_counts → /counts`, `GET /member_details → GET /{member_id}`, `/me/onboarding → /{gym_id}/onboarding`.

### Silent drops (NOT mentioned in `CRM_RESTORE.md` — worth a decision)
- **`'disabled'` gym onboarding status** removed from the CHECK constraint (old had 4 values, now 3). If a Stripe webhook ever maps to `disabled`, the DB write fails the constraint. *(verified)*
- **`PersonalInfo.waiver_id`** dropped from the member-detail schema (both FastAPI and Flutter).
- **`FastApiBackend/src/gyms/notes/`** — 7 markdown docs on the Connect onboarding flow, gone.
- **Members-list advanced filter** — old `MembersListFilterBar` + `MembersListFilterDialog` (status multiselect + date range) not rebuilt; current has only tab-switching + a visual-only no-op "Add Filter +" button.
- **Linked-account dialogs** — `ManageLinkedAccountsDialog` (view all + per-row unlink) and `LinkChildDialog` (add child from parent's page) not rebuilt, even though their backend endpoints exist.

---

## 4. Features GONE or UNUSED (present in this branch but dead / unwired / unfinished)

### 4a. Backend built, no Flutter caller (reachability-verified)
- **`ranks/*` — all 10 endpoints.** Zero CRM callers. `rank.dart`/`rank_summary.dart` models exist but no `RanksRepository`. *(verified)*
- **`rewards/*` — all 6 endpoints.** Zero CRM callers. `reward_card_model.dart` exists, no repository. *(verified)*
- **`membership_plans` mutations (7):** create/update/delete/get/set_price/migrate/migrate-all. CRM only calls `GET /` (list).
- **`discounts` mutations (3):** create/update/delete. CRM only calls `GET /` (list).
- **`classes/checkin` + `classes/streak`:** fully implemented; CRM has only TODO comments, no API call. Streak shown on the detail screen comes from the detail payload, not this endpoint.
- **`PUT /gyms/{id}` (update_gym):** no CRM caller.

### 4b. CRM calls a backend that doesn't exist
- 🟠 **`POST /members/{id}/refund`** — `member_repository.refundCharge()` + `RefundChargeDialog` exist and fire, but **no route is registered**. Will 404. `payments_stripe_payment_service.refund_payment()` is implemented but never exposed. *(verified)*

### 4c. DB tables with no FastAPI read/write path
- **7× `video_*`** — VideoService only (out of CRM scope, correct).
- **`gym_history`** — seed-only writer (`bootstrap/history.py`); no API reader.
- **`member_activities`** — zero FastAPI references (no reader, no writer).
- **`class_instance_exceptions`, `class_range_exceptions`** — schema + RLS exist; zero FastAPI references (deferred with the schedule UI).
- **`stripe_webhook_events`** — insert-only event log, never SELECTed.
- 🟠 **`member_invoice_line_items`, `member_invoice_applied_discounts`** — read by `member_details_transactions.sql` but **no `INSERT` anywhere**; the invoice-paid handler only writes `member_invoices`/`member_charges`. De-facto always empty. *(verified)*

### 4d. Orphaned Flutter code (defined, never imported)
- `members_list/data/models/rank_summary.dart` (+`.g.dart`) — self-referencing only.
- `members/presentation/widgets/members_filter_button.dart` — "visual-only no-op," never imported.
- `members/presentation/widgets/members_search_row.dart` — never imported (search is in `MembersListControls`).
- `members/presentation/widgets/specific_member/member_quick_list/member_quick_list.dart` — referenced only in a comment.
- `members_list/presentation/screens/members_list_screen.dart` — de-routed leftover (live screen is `members/presentation/screens/members_screen.dart`); `CRM_RESTORE.md` 3d defers its deletion.

### 4e. Intentionally unfinished ("the 25%", per `CRM_RESTORE.md` Part 7)
Refund initiation from UI · failed-payment retry/dunning UI · proration previews · Connect onboarding-completion handling. Backend data layers are mostly ready (webhooks record refunds/failures); the CRM-initiated paths are the gap.

### 4f. Stale artifacts (harmless, noisy)
~14 stale `.pyc` files under `Database/python_data/**/__pycache__/` and `FastApiBackend/src/members/**/__pycache__/` for removed/renamed/never-existed modules (incl. a `members_management_schema.pyc` and `members_service.pyc` with no source). One test bytecode `test_members_contact_fields.pyc` with no `.py`.

---

## 5. The one correction to flag
An early agent reported the `stripe_webhooks/service/handlers/` subpackage as "left behind." That is **wrong** — the dead-code pass verified all five files (`account_updated_handler`, `charge_refunded_handler`, `invoice_paid_handler`, `invoice_payment_failed_handler`, `stripe_time`) are **present**, just flattened from `handlers/` into `service/`, and fully wired. No webhook handler was lost.

---

## 6. Restore completeness scorecard

| Area | Status |
|---|---|
| `crm_user_id → member_id` re-key (all layers) | ✅ Complete, 0 residuals |
| `user_gym_* → member_*` table rename | ✅ Complete |
| Billing schema + tables restored | ✅ Complete |
| Billing RLS — service_role-write-only | ✅ Restored |
| Billing RLS — `hide_incomplete_stripe_records` on 4 `member_*` tables | 🔴 **Missing** (doc mandates it) |
| FastAPI billing domains (payments/memberships/plans/discounts/webhooks) | ✅ Restored + re-keyed |
| `members`/`gyms` router merge + Stripe Connect | ✅ Restored (multi-gym is new) |
| Flutter logic layer (bloc+data) restored | ✅ On disk (untracked) |
| Flutter member-detail UI rebuilt natively | ✅ 16 of ~18 dialogs |
| openapi.json regenerated | ✅ 43 → 63 operations |
| Restore committed to git | 🟠 **No** — staged/untracked working tree only |
| Invoice line-items / applied-discounts writer | 🟠 Absent |
| Refund endpoint | 🟠 CRM calls it; backend route absent |

---

## 7. Optional next actions (only if you want them)
1. 🔴 Add the `hide_incomplete_stripe_records` restrictive SELECT to the 4 `member_*` billing access-rules **or** amend `Database/CLAUDE.md` if the new direct-`members`-join is intentional (doc and SQL must agree).
2. Decide on the silent drops (`'disabled'` status, `waiver_id`, gyms `notes/`, members-list advanced filter, linked-account dialogs) — restore or document as intentional.
3. Either wire the CRM to the built-but-unused domains (ranks, rewards, plan/discount mgmt, check-in) or note them as a deliberate phase-2.
4. Add the refund route (or remove the dead CRM `refundCharge`/dialog) so the contract matches.
5. Add the line-items/applied-discounts writer to the invoice-paid handler, or drop the read if unused.
6. `git add` the untracked restore + clean stale `.pyc` files; fix the stale `AppManagementRoot` class name / `member_billing_profile` docstrings.
