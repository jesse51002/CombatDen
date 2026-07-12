# MVP TODO — engineering gaps

Snapshot from a 2026-07-07 audit (docs vault + codebase). Eng-scope only —
see chat history / `docs/` vault for the business-side validation gaps
(pricing re-derivation, switch-friendly-CRM list, validation bar) that are
tracked separately, not here.

## Not started / stubbed

- **Charging gym owners** — 0% built. No subscription/tier/platform-fee concept anywhere in the `gyms` schema or Stripe wiring. `gyms.stripe_account_id` is Connect routing for *member* payments only, unrelated. Needs: pricing model decided, schema, Stripe wiring, CRM/ops surface.

- **Growth / analytics page** — CRM screen exists (`features/growth/`, KPI tiles, donut stats, trend chart) but reads only `mock_growth.dart`. No backend `growth`/`analytics` domain exists. Docs vault confirms this matches committed scope ("engagement reporting" in `CombatDen_Strategy.md`).

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

## Notes / already more done than expected

- **Email auth (CRM/staff side)** — already fully built: Supabase login/register/auth-gate all live and gating the whole CRM app. The actual gap was narrower than originally assumed — it's mobile-app auth, not CRM auth itself.

- **Employees** — now built end to end (was "data model only, nothing wired," see git history). Identity is verified email (no `user_id` — both `gym_employees` and `members` dropped their auth FK; a verified Supabase account whose email matches a non-archived `gym_employees` row is that person's login, multi-gym native). 4 roles (`owner`/`admin`/`front_desk`/`trainer` — `front_desk` is new; trainers can now log in). Live `src/employees/` backend domain (GET/POST/PUT/DELETE, owner/admin-gated) + full CRM role enforcement (`EmployeeRole`/`RolePolicy`/`route_guard`/nav gating/`ForbiddenException`). Full model in the **`employees-guide`** skill.
  - **Deferred** (recorded, not built): the notification/invite email + resend (creating an employee sends nothing — the person must separately sign up with a matching email); the Add-New-Member CRM UI bridge (see above — the backend path exists, the CRM button doesn't call it yet); kiosk mode; un-archive/restore (re-hiring an archived person is a new row, not a reactivation).
