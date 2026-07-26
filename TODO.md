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

- **Email go-live — the BACKEND half is built; what's left is an account, DNS, and Dashboard toggles.** **Until the human steps below are done, staff onboarding is 100% non-functional in prod**, so read this before dismissing it.

  **Why it's non-negotiable:** identity is the **verified email** matched against a `gym_employees` row, and there is deliberately **no invite-token fallback**. If the GoTrue confirmation email never arrives, that person's `invite_status` sits at `pending` forever and they can never log in. The email *is* the access mechanism.

  **Why Supabase's built-in sender cannot do this job** (the trap that testing with your own address hides completely): it is capped at **2 messages/hour** and **refuses to deliver to any address that is not a member of your Supabase project's team** — it errors with "address not authorized". A real gym owner at `owner@theirgym.com` is not on your team, so they are not throttled, they are *rejected*.

  **Three separate mail channels, and only one of them is code.** Do not conflate them — each has its own setup step below:
  - **GoTrue / Supabase Auth** — the login confirmation + password-reset mail. Dashboard config.
  - **Stripe** — card-declined / dunning mail, sent from each gym's own connected account. Per-account config.
  - **CombatDen's own mail** (`FastApiBackend/src/emails/`) — the staff onboarding nudge and the member app invite. Code, and it is **built**.

  **DONE (code — built, nothing here is waiting on engineering):**
  - The `emails` domain — registry-driven kinds, `email_log` claim inside the triggering transaction + detached send, suppressions, the retry sweep as the reconciler's 6th step, `POST /api/v1/emails/send` and the public signed `GET /api/v1/emails/unsubscribe`.
  - The `email_log` + `email_suppressions` tables and their access rules (`Database/supabase/schemas/`).
  - Both create paths ask: `send_invite` is required on employee create and member create, and the response reports what actually happened (`queued` / `held` / `skipped_no_email` / `skipped_suppressed` / `not_requested`) instead of implying a send. The CRM adds a "Resend invite" affordance on any `pending` roster row.
  - Fail-safe defaults: `EMAIL_ENABLED_KINDS` is **empty**, so nothing sends until someone opts in, and every claim made before then is logged `held` — terminal by policy, never drained later.

  **NEEDS A HUMAN (in this order — the order matters, because enabling confirmations before mail works locks out every new signup, including you):**
  1. **Run the migration** `20260725233515_email_system.sql` (adds both tables + their enums).
  2. **Create the Resend account** and generate an API key. (Resend is the easiest here — 3k/mo free; SES is cheapest at volume, Postmark best for transactional deliverability.)
  3. **Verify the sending domain with DNS records (SPF + DKIM).** This is the step with a real wait — start it first. It serves BOTH the backend's own mail and Supabase's SMTP.
  4. **Supabase Dashboard → Authentication → SMTP:** host / port 587 / username / password, sender `noreply@combatden.net`.
  5. **Raise the post-SMTP rate limit off its 30/hour default** — one signup is one email, a 4-staff gym is four, an email change is two (`double_confirm_changes = true`), and password resets share the budget.
  6. **Then** enable Authentication → **Confirm email**, and flip `site_url` to `https://app.combatden.net` so confirmation links land on the CRM, not `localhost`.
  7. **Set the backend's env:** `RESEND_API_KEY`, `EMAIL_UNSUBSCRIBE_SECRET`, `EMAIL_UNSUBSCRIBE_BASE_URL`, and `EMAIL_ENABLED_KINDS` (start with `staff_onboarding`; add `member_app_invite` only once the member app is actually installable). Non-prod boxes want `EMAIL_SANDBOX_REDIRECT` — local mail does **not** land in Inbucket, because Inbucket only catches GoTrue's mail while our client talks to Resend over HTTPS regardless of the local stack.
  8. **Verify the per-connected-account Stripe customer-email toggles** at gym onboarding (successful-payment receipts, failed-payment notices, card-expiring warnings). This is the member-facing billing channel — see the next item; don't assume the defaults.

  - **Local dev needs none of this and is already done** for the GoTrue half — `config.toml` has `enable_confirmations = true` and confirmation mail is caught by Inbucket on `:54324`. `config.toml` governs *only* the local stack; the hosted project is configured entirely in the Dashboard.
  - Backend guard: `auth_autoconfirm_policy` defaults to `fail`, so the API refuses to boot against an auth stack that auto-confirms. That is intentional — it makes a misconfigured deploy loud instead of silently open.

- **Billing emails to members + the failed-payment end-action (per connected Stripe account)** — the **third** channel, distinct from both of the above: GoTrue carries only auth confirmation (the login identity link), and CombatDen's own `emails` domain carries only the staff onboarding nudge and the member app invite. **Neither sends a single piece of billing mail, and that is deliberate.** CombatDen sends **no payment receipts** — a monthly receipt is a monthly prompt to cancel — and **no overdue notices**: Stripe's Smart Retries already own the dunning conversation, and our `next_due_date` can read past-due while Stripe shows the member paid (a missed webhook the reconciler has not yet swept), so our version of that email would sometimes be simply wrong. Do not add billing mail to the `emails` domain without overturning that decision first.
  - **This is config, not a build.** Every Stripe write is a **direct charge** on the gym's own account (`PaymentsStripeClient.connect_opts` passes `stripe_account=<gym's account>`), so member-facing billing mail — payment receipts, card-declined notices, card-expiring warnings — is sent by **Stripe from the gym's own account and branding**. That is strictly better than writing it ourselves, and it is why the `emails` domain registers no billing kind. Verify these toggles are enabled on each connected account at onboarding; don't assume the defaults.
  - **The failed-payment end-action is already CANCEL — VERIFIED, no action needed.** Probed against the live test-mode Connect account with a test clock and a declining card: the subscription sat `past_due` at +10d and +20d, then Stripe **auto-cancelled it at ~+30d**. That is the branch that closes our recovery loop: `customer.subscription.deleted` → `CustomerSubscriptionDeletedHandler` → `bulk_payment_sync` → `PaymentSyncCancel` sets `cancel_date` and the member stops being active. (The other two branches — mark `unpaid`, leave `past_due` — would NOT close it; see below. Re-check only if a gym changes its Dashboard setting.)
  - **Caveat: the unpaid invoice survives the cancel.** The probe showed the renewal invoice still `open` after the subscription cancelled. So the debt does not disappear, but the CRM's Retry button resolves the invoice VIA the subscription — once the sub is gone, that invoice is only reachable in the Stripe Dashboard.
  - **Why the other branches leak money.** `PaymentSyncCancel` detects a dead sub by it being **not retrievable** (`resource_missing` on the subscription). An `unpaid` subscription still *exists*, so it is never detected as gone — and Stripe stops attempting its invoices, so the `invoice.payment_failed` events go quiet too. The membership stays `active` (the `member_memberships_status` view derives from `cancel_date`/`end_date`/freeze only — payment state is not in it), and **check-in is payment-blind**: `covers_reference` ignores `next_due_date`, and `CheckinWarning` has no payment reason (`no_membership`, `out_of_classes`, `ineligible_plan`, `over_capacity`, `unsigned_waiver`). Net: a non-paying member keeps training for free with no signal at the door. The only surviving trace is the Overdue list, since `next_due_date` advances only on `invoice.paid`.
  - **Done — the front desk now sees it at the counter.** `overdue` is a sixth `CheckinWarning`: a staff check-in of a past-due member is held with "Payment overdue" and a "Check in anyway" override. It **blocks a kiosk** (it is in `GateEvaluation.blocked`), so an unpaid member is sent to the front desk instead of self-admitting, while staff keep the "Check in anyway" override. Known caveat: `next_due_date` can read past-due while Stripe shows everything paid (a missed webhook the reconciler has not yet swept), so a kiosk rejection is occasionally a false alarm the desk has to clear. This makes a failed renewal visible at the one moment it is actionable, but it does **not** replace the Stripe settings above: without the cancel end-action the membership still never terminates on its own.

## Notes / already more done than expected
  - **Owner email is immutable for now** (future, non-blocking): `employees_update._enforce_owner_rules` rejects an owner changing their OWN email. Email is the sole identity link (no `user_id` FK), so a mistyped owner email would 403 the owner out of their own gym with no API recovery (an admin can't edit the owner row; the owner row can't be archived) — the freeze is a deliberate self-lockout guard. Build a proper owner-email-change flow with re-confirmation (verify the new address before it becomes the identity link) to lift it.
