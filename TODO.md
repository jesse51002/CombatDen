# MVP TODO — engineering gaps

Snapshot from a 2026-07-07 audit (docs vault + codebase). Eng-scope only —
see chat history / `docs/` vault for the business-side validation gaps
(pricing re-derivation, switch-friendly-CRM list, validation bar) that are
tracked separately, not here.

## Not started / stubbed

- **Charging gym owners** — 0% built. No subscription/tier/platform-fee concept anywhere in the `gyms` schema or Stripe wiring. `gyms.stripe_account_id` is Connect routing for *member* payments only, unrelated. Needs: pricing model decided, schema, Stripe wiring, CRM/ops surface.

- **Growth / analytics page** — DONE (PR #57). `FastApiBackend/src/growth/` computes 34 per-gym metrics at app launch + hourly into the `gym_growth_metrics` jsonb cache and serves them from `GET /api/v1/growth/`; display metadata is registry-owned, so adding a metric is one `.sql` file plus one registry line. The CRM's six tabs render the live envelopes (`mock_growth.dart` deleted), and a new `dormant` member status is surfaced in the members list. Deferred by decision: alerting on thresholds, CSV export (below), an earned-points chart (blocked — `members.points_balance` is a bare counter with no ledger, so points-over-time is unbuildable), and industry benchmarks.

- **Kiosk mode** — no kiosk UI/screen exists in CRM or MobileApp. Backend building block already exists: `checkin_member_gate.py` implements `is_member` true/false gating (member kiosk-reject vs staff-confirm) — reusable, not a rebuild.

- **Check-in QR code** — direction confirmed: **gym displays a QR (on the kiosk screen or a printed poster), member scans it with their phone to check in.** Currently 0% built on every layer:
  - No QR generation anywhere in FastApiBackend (zero backend code).
  - CRM's Settings → QR Codes section is fully mocked (`mock_qr_codes.dart`) — both `sign_up` and `check_in` entries point to the same placeholder image asset.
  - No scan-landing/deep-link handler exists for what happens when a member's phone camera reads the code.
  - Needs: backend endpoint to generate/serve a real per-gym (or per-class?) QR payload, a scan-landing flow (web link → check-in, likely gated by the same `is_member` logic kiosk mode reuses), and the CRM display to become real instead of a static image.
  - **Sign-up QR is cut from scope** — kiosk fully replaces it. Delete the `sign_up` mock entry + its unused placeholder asset when this section is touched (`CRM/lib/features/qr_codes/data/mock_qr_codes.dart`, `qr_code_sign_up.png`).

- **Add new member button** — the CRM UI is still stubbed: `members_list_controls.dart:72-79` shows a snackbar reading "Add Member flow is out of scope this pass" instead of opening a real flow. The backend path now exists (`POST /members`, callable by owner/admin/front_desk — see *Employees* below) and members can be created that way (seed scripts, direct API calls); what's missing is the CRM screen/dialog that calls it.

- **Mobile app — member auth** — 0% built. No login/session code exists anywhere in `MobileApp/lib` (confirmed via grep — only hit is unrelated `video_api_client.dart`). This blocks check-in QR scan-to-self-checkin, member self-service, and anything member-identity-scoped in the app.

- **Mobile app — core flows** — per `MobileApp/CLAUDE.md`, this is a **visual-only prototype**. Only the video feed and gym detail (classes/rewards, read-only) are live against VideoService/FastApiBackend. Home, booking, and profile are still mock. Needs real backend wiring to graduate out of prototype status — a substantial build, not a small task.

- **Landing page / one-pager rework for the full CRM** — not deeply audited yet; flagged as needed by Jesse, scope TBD.

- **Rank pictures update for the preset and also image default tray (just different colored belt images) when creating a new rank**

- Reporting and exporting to csv and tax info

## Blocks going live regardless of the above

- **FastApiBackend has no prod deployment yet** (`api.combatden.net` not live per README). CRM currently only works end-to-end against `localhost:8000`. Nothing above ships to a real gym until this exists.

- **Production SMTP on the hosted Supabase project** — deploy-time ops, not polish. **Without it, staff onboarding is 100% non-functional in prod**, so read this before dismissing it:
  - Identity is now the **verified email** matched against a `gym_employees` row, and there is deliberately **no invite-token fallback**. If the confirmation email never arrives, that person's `invite_status` sits at `pending` forever and they can never log in. The email *is* the access mechanism.
  - Supabase's **built-in** sender cannot do this job: it is capped at **2 messages/hour** and **refuses to deliver to any address that is not a member of your Supabase project's team** (it errors with "address not authorized"). A real gym owner at `owner@theirgym.com` is not on your team, so they are not throttled — they are *rejected*. Testing with your own address hides this completely.
  - Steps, in this order (the order matters — enabling confirmations before mail works locks out every new signup, **including you**):
    1. Pick a provider — Resend is the easiest here (3k/mo free), SES the cheapest at volume, Postmark the best transactional deliverability.
    2. Verify `combatden.net` with their DNS records (SPF + DKIM). This is the step with a real wait; do it first.
    3. Supabase Dashboard → Authentication → SMTP: host / port 587 / username / password, sender `noreply@combatden.net`.
    4. Raise the post-SMTP rate limit off its **30/hour** default — one signup is one email, a 4-staff gym is four, an email change is two (`double_confirm_changes = true`), and password resets share the budget.
    5. **Then** enable Authentication → Confirm email.
  - Also flip `site_url` to `https://app.combatden.net` so confirmation links land on the CRM, not `localhost`.
  - **Local dev needs none of this and is already done** — `config.toml` has `enable_confirmations = true` and mail is caught by Inbucket on `:54324`. `config.toml` governs *only* the local stack; the hosted project is configured entirely in the Dashboard.
  - Backend guard: `auth_autoconfirm_policy` defaults to `fail`, so the API refuses to boot against an auth stack that auto-confirms. That is intentional — it makes a misconfigured deploy loud instead of silently open.

## Notes / already more done than expected

- **Email auth (CRM/staff side)** — already fully built: Supabase login/register/auth-gate all live and gating the whole CRM app. The actual gap was narrower than originally assumed — it's mobile-app auth, not CRM auth itself.

- **Employees** — now built end to end (was "data model only, nothing wired," see git history). Identity is verified email (no `user_id` — both `gym_employees` and `members` dropped their auth FK; a verified Supabase account whose email matches a non-archived `gym_employees` row is that person's login, multi-gym native). 4 roles (`owner`/`admin`/`front_desk`/`trainer` — `front_desk` is new; trainers can now log in). Live `src/employees/` backend domain (GET/POST/PUT/DELETE — the list read is STAFF so front desk fills the schedule instructor picker, the writes are owner/admin) + full CRM role enforcement (`EmployeeRole`/`RolePolicy`/`route_guard`/nav gating/`ForbiddenException`). Full model in the **`employees-guide`** skill.
  - **Deferred** (recorded, not built): the notification/invite email + resend (creating an employee sends nothing — the person must separately sign up with a matching email); the Add-New-Member CRM UI bridge (see above — the backend path exists, the CRM button doesn't call it yet); kiosk mode; un-archive/restore (re-hiring an archived person is a new row, not a reactivation).
  - **Owner email is immutable for now** (future, non-blocking): `employees_update._enforce_owner_rules` rejects an owner changing their OWN email. Email is the sole identity link (no `user_id` FK), so a mistyped owner email would 403 the owner out of their own gym with no API recovery (an admin can't edit the owner row; the owner row can't be archived) — the freeze is a deliberate self-lockout guard. Build a proper owner-email-change flow with re-confirmation (verify the new address before it becomes the identity link) to lift it.
