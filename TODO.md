# MVP TODO — engineering gaps

Snapshot from a 2026-07-07 audit (docs vault + codebase). Eng-scope only —
see chat history / `docs/` vault for the business-side validation gaps
(pricing re-derivation, switch-friendly-CRM list, validation bar) that are
tracked separately, not here.

## Not started / stubbed

- **Charging gym owners** — 0% built. No subscription/tier/platform-fee concept anywhere in the `gyms` schema or Stripe wiring. `gyms.stripe_account_id` is Connect routing for *member* payments only, unrelated. Needs: pricing model decided, schema, Stripe wiring, CRM/ops surface.

- **Kiosk mode — two follow-ups left; the kiosk itself is BUILT.** `CRM/lib/features/kiosk/` is the member-facing self-serve surface that runs on the gym's front-desk iPad inside the authenticated CRM: the check-in lane (name search → class pick → the glance, on the backend's strict `is_member: true` gate in `checkin_member_gate.py`) and the full solo + group self-serve signup lane (payer seating, plan pick, waiver sign, card, per-person results receipt, decline retry). The kiosk is CRM-only by design — the MobileApp is the member's own phone client, not a kiosk host. Deep contract: the `kiosk-guide` skill. Still not started:
  - **Phase G — the rotating check-in QR.** The kiosk home's QR is a deliberately inert glyph. The design (hourly server-minted per-gym tokens, a new `src/kiosk/` backend domain, the member-portal scan-checkin route) is DESIGN ONLY in `PHASE_G_QR_PLAN.md`, whose §10 open questions are unanswered.
  - **The per-gym app-download page** the separate "Get the app" QR points at (mockup: `APP_DOWNLOAD_PAGE_MOCKUP.html`). The backend half has shipped (`gyms.app_store_url` / `play_store_url` + the public read) and the kiosk already encodes the right URL, so what is missing is the page.

- **Mobile app — member auth** — 0% built. No login/session code exists anywhere in `MobileApp/lib` (confirmed via grep — only hit is unrelated `video_api_client.dart`). This blocks check-in QR scan-to-self-checkin, member self-service, and anything member-identity-scoped in the app.

- **Mobile app — core flows** — per `MobileApp/CLAUDE.md`, this is a **visual-only prototype**. Only the video feed and gym detail (classes/rewards, read-only) are live against VideoService/FastApiBackend. Home, booking, and profile are still mock. Needs real backend wiring to graduate out of prototype status — a substantial build, not a small task.

- **Landing page / one-pager rework for the full CRM** — not deeply audited yet; flagged as needed by Jesse, scope TBD.


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

- **Billing emails to members + the failed-payment end-action (per connected Stripe account)** — a **different channel** from the Supabase SMTP item above, which only carries *auth confirmation* email (the login identity link) and sends no billing mail at all. The app itself sends **zero** outbound member email: there is no SendGrid / Resend / SES / Postmark / Twilio / SMTP integration anywhere in `FastApiBackend/src` or `CRM/lib`, by design.
  - **This is config, not a build.** Every Stripe write is a **direct charge** on the gym's own account (`PaymentsStripeClient.connect_opts` passes `stripe_account=<gym's account>`), so member-facing billing mail — payment receipts, card-declined notices, card-expiring warnings — is sent by **Stripe from the gym's own account and branding**. That is strictly better than building an email service, and it is why no email provider belongs in the backend. Verify these are enabled on each connected account at onboarding; don't assume the defaults.
  - **The failed-payment end-action is already CANCEL — VERIFIED, no action needed.** Probed against the live test-mode Connect account with a test clock and a declining card: the subscription sat `past_due` at +10d and +20d, then Stripe **auto-cancelled it at ~+30d**. That is the branch that closes our recovery loop: `customer.subscription.deleted` → `CustomerSubscriptionDeletedHandler` → `bulk_payment_sync` → `PaymentSyncCancel` sets `cancel_date` and the member stops being active. (The other two branches — mark `unpaid`, leave `past_due` — would NOT close it; see below. Re-check only if a gym changes its Dashboard setting.)
  - **Caveat: the unpaid invoice survives the cancel.** The probe showed the renewal invoice still `open` after the subscription cancelled. So the debt does not disappear, but the CRM's Retry button resolves the invoice VIA the subscription — once the sub is gone, that invoice is only reachable in the Stripe Dashboard.
  - **Why the other branches leak money.** `PaymentSyncCancel` detects a dead sub by it being **not retrievable** (`resource_missing` on the subscription). An `unpaid` subscription still *exists*, so it is never detected as gone — and Stripe stops attempting its invoices, so the `invoice.payment_failed` events go quiet too. The membership stays `active` (the `member_memberships_status` view derives from `cancel_date`/`end_date`/freeze only — payment state is not in it), and **check-in is payment-blind**: `covers_reference` ignores `next_due_date`, and `CheckinWarning` has no payment reason (`no_membership`, `out_of_classes`, `ineligible_plan`, `over_capacity`, `unsigned_waiver`). Net: a non-paying member keeps training for free with no signal at the door. The only surviving trace is the Overdue list, since `next_due_date` advances only on `invoice.paid`.
  - **Done — the front desk now sees it at the counter.** `overdue` is a sixth `CheckinWarning`: a staff check-in of a past-due member is held with "Payment overdue" and a "Check in anyway" override. It **blocks a kiosk** (it is in `GateEvaluation.blocked`), so an unpaid member is sent to the front desk instead of self-admitting, while staff keep the "Check in anyway" override. Known caveat: `next_due_date` can read past-due while Stripe shows everything paid (a missed webhook the reconciler has not yet swept), so a kiosk rejection is occasionally a false alarm the desk has to clear. This makes a failed renewal visible at the one moment it is actionable, but it does **not** replace the Stripe settings above: without the cancel end-action the membership still never terminates on its own.

## Notes / already more done than expected
  - **Owner email is immutable for now** (future, non-blocking): `employees_update._enforce_owner_rules` rejects an owner changing their OWN email. Email is the sole identity link (no `user_id` FK), so a mistyped owner email would 403 the owner out of their own gym with no API recovery (an admin can't edit the owner row; the owner row can't be archived) — the freeze is a deliberate self-lockout guard. Build a proper owner-email-change flow with re-confirmation (verify the new address before it becomes the identity link) to lift it.
