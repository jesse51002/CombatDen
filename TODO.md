# MVP TODO — engineering gaps

Snapshot from a 2026-07-07 audit (docs vault + codebase). Eng-scope only —
see chat history / `docs/` vault for the business-side validation gaps
(pricing re-derivation, switch-friendly-CRM list, validation bar) that are
tracked separately, not here.

## Not started / stubbed

- **Charging gym owners** — 0% built. No subscription/tier/platform-fee concept anywhere in the `gyms` schema or Stripe wiring. `gyms.stripe_account_id` is Connect routing for *member* payments only, unrelated. Needs: pricing model decided, schema, Stripe wiring, CRM/ops surface.

- **Kiosk mode** — no kiosk UI/screen exists in CRM or MobileApp. Backend building block already exists: `checkin_member_gate.py` implements `is_member` true/false gating (member kiosk-reject vs staff-confirm) — reusable, not a rebuild.

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
  - **The load-bearing one is the failed-payment end-action — set it to _cancel the subscription_.** Stripe's behaviour after retries are exhausted is configurable (cancel / mark `unpaid` / leave `past_due`) with no universal default, and only the **cancel** branch closes our recovery loop: `customer.subscription.deleted` → `CustomerSubscriptionDeletedHandler` → `bulk_payment_sync` → `PaymentSyncCancel` sets `cancel_date` and the member stops being active.
  - **Why the other branches leak money.** `PaymentSyncCancel` detects a dead sub by it being **not retrievable** (`resource_missing` on the subscription). An `unpaid` subscription still *exists*, so it is never detected as gone — and Stripe stops attempting its invoices, so the `invoice.payment_failed` events go quiet too. The membership stays `active` (the `member_memberships_status` view derives from `cancel_date`/`end_date`/freeze only — payment state is not in it), and **check-in is payment-blind**: `covers_reference` ignores `next_due_date`, and `CheckinWarning` has no payment reason (`no_membership`, `out_of_classes`, `ineligible_plan`, `over_capacity`, `unsigned_waiver`). Net: a non-paying member keeps training for free with no signal at the door. The only surviving trace is the Overdue list, since `next_due_date` advances only on `invoice.paid`.
  - **Done — the front desk now sees it at the counter.** `overdue` is a sixth `CheckinWarning`: a staff check-in of a past-due member is held with "Payment overdue" and a "Check in anyway" override. It is deliberately **absent from `GateEvaluation.blocked`**, so a kiosk scan still admits normally — a past-due date is often a false alarm (a retry in flight, cash not yet recorded) and billing is not a legal gate the way the waiver is. This makes a failed renewal visible at the one moment it is actionable, but it does **not** replace the Stripe settings above: without the cancel end-action the membership still never terminates on its own.

## Notes / already more done than expected
  - **Owner email is immutable for now** (future, non-blocking): `employees_update._enforce_owner_rules` rejects an owner changing their OWN email. Email is the sole identity link (no `user_id` FK), so a mistyped owner email would 403 the owner out of their own gym with no API recovery (an admin can't edit the owner row; the owner row can't be archived) — the freeze is a deliberate self-lockout guard. Build a proper owner-email-change flow with re-confirmation (verify the new address before it becomes the identity link) to lift it.
