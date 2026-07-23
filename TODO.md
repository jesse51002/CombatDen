# MVP TODO — engineering gaps

Snapshot from a 2026-07-07 audit (docs vault + codebase). Eng-scope only —
see chat history / `docs/` vault for the business-side validation gaps
(pricing re-derivation, switch-friendly-CRM list, validation bar) that are
tracked separately, not here.

## Not started / stubbed

- **Charging gym owners** — 0% built. No subscription/tier/platform-fee concept anywhere in the `gyms` schema or Stripe wiring. `gyms.stripe_account_id` is Connect routing for *member* payments only, unrelated. Needs: pricing model decided, schema, Stripe wiring, CRM/ops surface.

- **Growth / analytics page** — CRM screen exists (`features/growth/`, KPI tiles, donut stats, trend chart) but reads only `mock_growth.dart`. No backend `growth`/`analytics` domain exists. Docs vault confirms this matches committed scope ("engagement reporting" in `CombatDen_Strategy.md`).

- **Kiosk mode** — no kiosk UI/screen exists in CRM or MobileApp. Backend building block already exists: `checkin_member_gate.py` implements `is_member` true/false gating (member kiosk-reject vs staff-confirm) — reusable, not a rebuild.

- **Mobile app — member auth** — 0% built. No login/session code exists anywhere in `MobileApp/lib` (confirmed via grep — only hit is unrelated `video_api_client.dart`). This blocks check-in QR scan-to-self-checkin, member self-service, and anything member-identity-scoped in the app.

- **Mobile app — core flows** — per `MobileApp/CLAUDE.md`, this is a **visual-only prototype**. Only the video feed and gym detail (classes/rewards, read-only) are live against VideoService/FastApiBackend. Home, booking, and profile are still mock. Needs real backend wiring to graduate out of prototype status — a substantial build, not a small task.

- **Landing page / one-pager rework for the full CRM** — not deeply audited yet; flagged as needed by Jesse, scope TBD.

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
  - **Owner email is immutable for now** (future, non-blocking): `employees_update._enforce_owner_rules` rejects an owner changing their OWN email. Email is the sole identity link (no `user_id` FK), so a mistyped owner email would 403 the owner out of their own gym with no API recovery (an admin can't edit the owner row; the owner row can't be archived) — the freeze is a deliberate self-lockout guard. Build a proper owner-email-change flow with re-confirmation (verify the new address before it becomes the identity link) to lift it.
