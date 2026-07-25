# CombatDen — Manual Setup & Configuration

This is the runbook of **manual, human-only** setup steps for CombatDen — the
things a person has to do **by hand in an external dashboard** (Stripe, Supabase,
the domain registrar / AWS) or provision manually, that are **not** performed by
any code or by the deploy scripts. It exists so these steps stop living only in
chat and memory, and can't be forgotten when onboarding a new environment or
scaling up.

This is **not** the deploy runbook — `DEPLOYMENT.md` owns build/deploy
(S3 / CloudFront / ACM / App Runner). This doc references it for the manual
actions it involves and never duplicates it.

> **Keep this doc growing.** Whenever you discover a new step that a human must
> do by hand (a new Stripe Dashboard toggle, a Supabase auth setting, a DNS
> record, a provider key, a one-time provision), **add it here in the same
> change.** Every step below is grounded in a real source (a repo file or a
> founder decision); if you add one, ground it too. Anything you suspect but
> can't ground goes under **To confirm** at the bottom, never asserted as fact.

---

## Stripe (platform account)

These are **platform-level** settings on your own Stripe platform account. Each applies to **every** connected (gym) account automatically — you do NOT configure them per gym. **Set each one in BOTH Test and Live mode** — Test and Live are separate and it is easy to have something working in test and forget it for production.

### Block "Link" for connected accounts — REQUIRED
Card entry (kiosk and CRM) tokenizes in the **connected account's** context (each gym's own Stripe account), so the *connected account's* Link setting governs the "Save with Link" prompt during card entry. A saved third-party wallet on a shared front-desk iPad is wrong for the kiosk (the fresh-card law: only a freshly-entered card, never a saved one).

- **Dashboard → Settings (gear) → Connect → Payment methods** ("Manage payment methods for your connected accounts") → **Link** → set to **Blocked**.
- Use **Blocked**, not just Off: a gym cannot re-enable Link on its own account, and the single setting covers all current and future gyms.
- **Verify:** re-run the kiosk card step; the "Save with Link" prompt no longer appears.
- Note: the pinned `flutter_stripe_web` package exposes no code lever to disable Link, so this platform setting is the supported mechanism — there is intentionally no code for it.

### Enable the Radar card-testing rule — STRONGLY RECOMMENDED
The kiosk is an unattended device that accepts card entry — a card-testing vector. Stripe Radar's cross-merchant rule is the platform-level defense that the client-side decline cooldown cannot replicate.

- **Dashboard → Radar → Rules** → enable the free canned rule **"Block if a card was tested at multiple merchants in a short window."**

### Customer emails — Stripe owns receipts AND overdue notices — VERIFY
CombatDen deliberately sends **no** payment receipt and **no** overdue/dunning email of its own. Every charge is a **direct charge** on the gym's own connected account (`PaymentsStripeClient.connect_opts` passes `stripe_account=<the gym's id>`, `FastApiBackend/src/payments/service/payments_stripe_client.py:39`) and each Stripe Customer is created with the **member's own email** (`FastApiBackend/src/members/service/management/members_management_create.py:200`) — so Stripe already mails the member a gym-branded receipt, a card-declined notice, and its Smart Retries dunning sequence, ending in the auto-cancel confirmed by probe (`past_due` at +10d and +20d, cancelled ~+30d). Ours would duplicate those, and would sometimes fire wrongly: `next_due_date` advances only on `invoice.paid`, so a webhook the reconciler has not yet swept leaves a member reading past-due while Stripe shows them fully paid.

**That makes Stripe's customer-email settings load-bearing product behaviour, not a detail — if they are off, the member gets nothing about their money from anyone.**

- **Dashboard → Settings (gear) → Business → Customer emails** → confirm **Successful payments** and **Refunds** are set the way you want them.
- Who owns the toggle depends on the account type. For accounts with the full Dashboard the *connected account* owns it; for **Express** accounts — which is what CombatDen creates (`STRIPE_EXPRESS_ACCOUNT_TYPE = "express"`, `FastApiBackend/src/gyms/service/gyms_stripe_connect_service.py:18`) — the gym only gets the limited Express Dashboard and cannot reach that screen, so per Stripe's docs the **platform** configures it via `settings.branding`. Treat the exact lever as **unconfirmed** until probed — see *To confirm* below.
- **Set in BOTH Test and Live mode.**
- **Verify:** run one real test-mode charge against a connected account and confirm the email actually lands in the *member's* inbox — not yours, and not the gym owner's.

### Per-gym: Stripe Connect onboarding
Each gym completes Stripe Connect onboarding (Stripe's hosted flow) before it can take payments. Until then the gym's `stripe_account_id` is null, and the kiosk/CRM correctly refuse card entry (payments unavailable) rather than erroring. This is completed by the gym owner, not the platform operator.

### Register the Stripe Connect webhook endpoint — REQUIRED
The backend requires a **webhook signing secret** (`STRIPE_CONNECT_WEBHOOK_SECRET`,
a required `Settings` field with no default — `FastApiBackend/src/core/config.py`)
to verify inbound Stripe events. You obtain that secret by **registering a webhook
endpoint in the Stripe Dashboard**; the code cannot create it for you.

- Point a **Connect** webhook endpoint at the backend's public URL:
  **`POST {backend}/api/v1/stripe/webhooks`**
  (route + signature verification against `stripe_connect_webhook_secret`:
  `FastApiBackend/src/stripe_webhooks/stripe_webhooks_router.py`).
- Subscribe it to the events the backend actually handles (the `EVENT_*`
  constants in `FastApiBackend/src/stripe_webhooks/service/stripe_webhooks_service.py`):
  `invoice.paid`, `invoice_payment.paid`, `invoice.payment_failed`,
  `refund.created`, `refund.updated`, `account.updated`,
  `customer.subscription.deleted`.
- Copy the endpoint's **signing secret** (`whsec_…`) into
  `STRIPE_CONNECT_WEBHOOK_SECRET` (see *Environment & secrets* below).
- **Do this in BOTH Test and Live mode** — each mode issues its own endpoint and
  its own signing secret.

### Stripe Connect Express onboarding config (env, not Dashboard)
The hosted onboarding flow reads three operator-set values from the backend env
(`FastApiBackend/.env.example`): `STRIPE_CONNECT_REFRESH_URL`,
`STRIPE_CONNECT_RETURN_URL` (where Stripe returns the owner after onboarding), and
`STRIPE_CONNECT_EXPRESS_COUNTRY` (default `US`). Set these to real deployed URLs —
see *Environment & secrets*.

---

## Supabase

### Hosted project — SMTP sender + email confirmations ON
Identity in CombatDen is the **verified email claim** (the JWT `email` joined
live against `gym_employees.email` / `members.email`). Email confirmations must
stay ON, or anyone could sign up as an existing owner's address and take over
that gym.

- Keep **email confirmations enabled**. Locally this is `config.toml`
  `[auth.email] enable_confirmations = true`; the **hosted project is configured
  separately in the Supabase Dashboard and needs a working SMTP sender** so
  confirmation mail is actually delivered (`Database/CLAUDE.md` → *Security*).
- The backend enforces this at boot: `AuthSettingsGuard` reads GoTrue's published
  config and **refuses to start** if auto-confirm is on (default policy `fail`)
  — see `FastApiBackend/CLAUDE.md` → *Startup guard on GoTrue's auto-confirm*. If
  the guard trips, fix the auth config; do not work around it.

### Local dev gotcha — restart Kong after `supabase db reset`
After `supabase db reset` (or any reset that **recreates** containers), auth calls
can return **502 Bad Gateway** from `http://127.0.0.1:54321/auth/v1/...` even
though every container shows healthy. `db reset` recreates the GoTrue/db/storage
containers with new IPs but does **not** recreate the **Kong** gateway, which
keeps a stale upstream for the old auth IP.

- **Fix:** `docker restart supabase_kong_Gymworld`, then confirm
  `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:54321/auth/v1/health`
  returns `200`, then re-run the seed. This is not a code bug.
  (Source: project memory `project_supabase_reset_kong_502.md`.)

### Local dev gotcha — restart the stack after changing `enable_confirmations`
GoTrue reads `enable_confirmations` **at container start**, so `supabase db reset`
does **not** apply a change to it. To change that flag you must
**`supabase stop && supabase start`** — not a reset/reseed
(`FastApiBackend/CLAUDE.md` → *Startup guard on GoTrue's auto-confirm*).

---

## Database migrations (human-run)

Migrations are **hand-authored and run by the founder — never by an agent.** This
is a hard rule (`Database/CLAUDE.md` → *Schema workflow*):

- Migrations are **hand-written to match the `schemas/` / `access_rules/` end
  state; never auto-generated** (`supabase db diff` strips `security_invoker`,
  drops objects destructively, and misses enum retirements).
- **The founder runs every migration and seed command manually**
  (`supabase db reset`, `supabase migration up`, `python python_data/main.py`) —
  agents must not execute them.
- **After any merge that brings in migrations, check for duplicate version
  prefixes before running anything** (a version collision is a silent merge
  hazard git will not flag):
  ```
  cd Database/supabase/migrations && for f in *.sql; do echo "${f%%_*}"; done | sort | uniq -d
  ```
  Any output is a duplicated `YYYYMMDDHHMMSS` prefix — resolve it (renumber the
  unmerged side) before `make reset` / `make start`.

For production content: schema is applied via Supabase migrations from
`Database/` that **you run**; never `supabase db pull` while local schema is ahead
of prod (it generates a destructive migration). See `DEPLOYMENT.md` →
*VideoService (read API retired) → Prod content sync*.

---

## DNS & AWS one-time provisioning

The domain's DNS is **manual at Squarespace** (the registrar). The AWS deploy
scripts do not touch DNS — when you provision or re-provision any hosted service,
the scripts **print** the cert-validation and CNAME records, and **you add them by
hand** at Squarespace.

`DEPLOYMENT.md` is the authoritative runbook for the exact records and the
provision → validate → finalize order. Do not duplicate them here — the only
manual actions to remember:

- **Add the printed records at Squarespace** and wait for ACM cert validation
  (~5 min) / CloudFront deploy (~5 min) between steps. See `DEPLOYMENT.md` →
  *DNS records to add at Squarespace* and *ThemeService assets — S3 + CloudFront*.
- **The Squarespace Host field is base-domain-relative** — Squarespace
  auto-appends `combatden.net`, so paste the host **without** it (e.g. `cdn`, not
  `cdn.combatden.net`) or it doubles. The Value (cert target / CloudFront domain)
  keeps its full form and trailing dot. (`DEPLOYMENT.md` → *DNS Host field is
  base-domain-relative*.)
- **Post-demo platform move:** App Runner is demo-only; the plan is to move the
  theme + video services to Amazon ECS Express Mode after the demo — a manual
  operator action (`DEPLOYMENT.md` → *Platform note* and *Combined backend +
  worker image*). The retired standalone VideoService read API leaves an
  **orphaned App Runner service** to pause/delete by hand
  (`DEPLOYMENT.md` → *VideoService (read API retired)*).

---

## Environment & secrets provisioning

None of these are in git (every per-system env file is gitignored), and the
production platform **injects them at container start** — so provisioning them is
always a manual step. **Never commit real values; describe only the shape.** Each
system ships a `.env.example` documenting its keys.

### Local dev / worktrees
A fresh checkout or worktree has **no** env files, so every system + its
tests/seed fail until they're present. On Jesse's machine, from inside a new
worktree run the local gitignored helper
**`/var/home/jm/Documents/CombatDen/codebase/setup_worktree_env.sh`**, which
deterministically copies each per-system env file from the root checkout and
symlinks the poetry `.venv`s and large untracked data dirs (`CLAUDE.md` →
*Worktrees*; the script itself). The env files it copies:

- `FastApiBackend/.env`
- `CRM/.env.dev`, `CRM/.env.prod`
- `Database/python_data/.env`
- `VideoService/.env`, `VideoService/.env.prod`
- `ThemeService/.env`

### What each env file holds (names only — see each `.env.example`)
- **`FastApiBackend/.env`** — Supabase (`SUPABASE_URL`, `SUPABASE_ANON_KEY`,
  `SUPABASE_SERVICE_ROLE_KEY`), Stripe (`STRIPE_SECRET_KEY`,
  `STRIPE_WEBHOOK_SECRET`, `STRIPE_CONNECT_WEBHOOK_SECRET`), Stripe Connect
  Express (`STRIPE_CONNECT_REFRESH_URL`, `STRIPE_CONNECT_RETURN_URL`,
  `STRIPE_CONNECT_EXPRESS_COUNTRY`), `DATABASE_URL`, `YOUTUBE_API_KEY`, and the
  optional video/LLM keys (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`,
  `GEMINI_API_KEY`). Full list: `FastApiBackend/.env.example` and
  `deploy/CLAUDE.md` → *Runtime environment variables*.
- **`CRM/.env.dev` / `.env.prod`** — `API_BASE_URL` (the backend URL the app
  calls), `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `STRIPE_PUBLISHABLE`
  (`CRM/.env.example`).
- **`Database/python_data/.env`** — `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`,
  `SUPABASE_ANON_KEY`, `BACKEND_URL`, and a Stripe **test-mode**
  `STRIPE_SECRET_KEY` for the overdue-member seed path
  (`Database/python_data/.env.example`).
- **`VideoService/.env` / `.env.prod`** — `DATABASE_URL` (shared Supabase
  Postgres), plus the worker keys `YOUTUBE_API_KEY`, `APIFY_TOKEN`,
  `GEMINI_API_KEY`, `OPENAI_API_KEY` (`VideoService/.env.example`).
- **`ThemeService/.env`** — provider keys `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`,
  `OPENAI_API_KEY`, `RECRAFT_API_KEY`, `GOOGLE_FONTS_API_KEY`
  (`ThemeService/.env.example`).

### External API keys you must provision by hand
Each of these is registered at a third-party console (grounded in the
`.env.example` comments):

- **Stripe** secret + publishable keys, and the webhook signing secret(s) from
  the registered endpoint (see *Stripe* above) — Stripe Dashboard.
- **Supabase** project URL + `anon` / `service_role` keys — Supabase Dashboard.
- **YouTube Data API** key — Google Cloud (free within the daily quota; a quota
  increase is a free Google Cloud request).
- **Apify** token — apify.com (the enrich-stage transcript fetch).
- **Recraft** key — recraft.ai (ThemeService icon SVG + background removal).
- **Google Fonts Developer API** key — Google Fonts (font validation).
- **Anthropic / OpenAI / Gemini** keys — the respective provider consoles (LLM /
  embedding calls).

### Production runtime env (deploy image)
For the combined backend + worker image there is **no baked config** — the
platform injects every secret/config value at container start. The authoritative
name list is each app's `src/core/config.py` `Settings` class, summarized in
`deploy/CLAUDE.md` → *Runtime environment variables*.

---

## To confirm

Open questions surfaced during research — **not** asserted as setup steps until
resolved:

- **`STRIPE_WEBHOOK_SECRET` (non-Connect) is required to boot but consumed
  nowhere.** It is declared as a required `Settings` field with no default
  (`FastApiBackend/src/core/config.py:63`), so the backend will not start without
  it — yet no code path reads it: the webhook router verifies **only** against
  `stripe_connect_webhook_secret`
  (`FastApiBackend/src/stripe_webhooks/stripe_webhooks_router.py:70`), and grep
  finds no other use of `stripe_webhook_secret` in `src/`. Confirm whether a
  separate (non-Connect) webhook endpoint is intended — in which case its manual
  registration belongs in the *Stripe* section above — or whether the field is
  vestigial and should be dropped from `Settings` (so it stops being a required
  env var with no purpose).

- **Which Stripe customer emails an Express gym's members actually receive, and
  who controls them.** CombatDen ships no receipt email and no overdue email on
  the basis that Stripe sends both (see *Stripe → Customer emails* above), so
  this is a load-bearing assumption that has never been verified end to end.
  Three things to settle on a live Express test account, ideally with a test
  clock — the same method that confirmed the failed-payment end-action
  auto-cancels at ~+30d:
  1. What does a member actually receive today on a **successful** charge, and
     on a **declined** one? (Confirm it reaches the member, not the platform.)
  2. Can the **platform** turn those on or off for a connected account via
     `settings.branding`, or is the limited Express Dashboard genuinely the only
     lever — meaning each gym owner has to be walked through it at onboarding?
  3. **Does a member with no card on file — or one who pays cash via
     `mark_paid_cash` — receive any Stripe dunning at all?** Smart Retries has
     nothing to retry without a card, and Stripe's *invoice reminders* are a
     separate setting from subscription dunning. If this leaves a silent gap,
     it is the one case where CombatDen would need to send its own overdue
     email after all.
