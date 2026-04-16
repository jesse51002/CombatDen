# Error handling

The backend is the source of truth for every decision in this
flow. Your job on the frontend is to (a) show good copy for
each failure mode, (b) decide what to retry vs. what to bail
on, and (c) never cache assumptions across network calls.

## HTTP status → UX mapping

Applies to all three endpoints. Status codes that are not
listed for a given endpoint in `02_api_reference.md` can be
treated as "should not happen, show generic error".

| Status | Meaning                                      | User-facing copy                                                       | Action                                          |
|--------|----------------------------------------------|------------------------------------------------------------------------|-------------------------------------------------|
| 200    | OK (status endpoints)                        | —                                                                      | Update UI based on payload                      |
| 201    | OK (create endpoint)                         | —                                                                      | Open onboarding URL                             |
| 400    | Invalid input                                | "Please check your info and try again."                                | Return to the form                              |
| 401    | Not authenticated                            | "Your session has expired. Please sign in again."                      | Bounce to login                                 |
| 404    | No gym / Stripe account missing              | —                                                                      | Route to the create wizard                      |
| 409    | Conflict (see detail string switch below)    | Depends on `detail`                                                    | Depends on `detail`                             |
| 502    | Stripe is unavailable                        | "Stripe is unavailable right now. Please try again."                   | Show retry button                               |
| 500    | Server error                                 | "Something went wrong. Please try again."                              | Show retry button                               |
| Network timeout / offline | —                                 | "Network error. Check your connection and try again."                  | Show retry button                               |

## `409 Conflict` — switch on `detail`

On `POST /api/v1/gyms/` (create), the `detail` string is one of:

| Detail                                                | User-facing copy                                        | Action                                                              |
|-------------------------------------------------------|---------------------------------------------------------|---------------------------------------------------------------------|
| `Gym already set up`                                  | —                                                       | Navigate straight to home                                           |
| `Finish onboarding: GET /api/v1/gyms/me/onboarding`   | "Continuing your Stripe setup..."                       | Call `GET /me/onboarding`, resume flow based on result              |
| `Gym Stripe account is disabled, contact support`     | "Your Stripe account is disabled. Please contact support." | Terminal error UI with a "Contact support" link                 |

On `POST /api/v1/gyms/me/onboarding/link`, a 409 means the gym
is no longer in `pending` state (it has flipped to `complete`
or `disabled` since you last checked). Call `GET /me/onboarding`
to find out which and route accordingly.

Any other 409 `detail` string is unknown territory — show a
generic error and route back to the bootstrap check.

## Retry policy

Apply at the fetch layer so every call benefits. Only retry on:

- Network errors (timeout, DNS failure, connection reset)
- HTTP 502, 503, 504

Never retry:

- 4xx (validation / auth / conflict — retrying won't help)
- 500 (may be a deterministic bug — let the user retry manually)

Back-off schedule for one-shot calls: at most 2 automatic
retries at 1s and 2s, then surface the error to the UI. The
"retry" button on the recoverable error screen is the
manual-retry layer on top.

The **poller** has its own backoff discipline described in
`03_polling.md`: 10s on success, 15s → 30s → 60s on consecutive
errors, reset to 10s on the next 200. The poller never stops
automatically on a transient failure — it keeps trying because
the user is still mid-setup and needs the eventual answer.

**Never retry `POST /api/v1/gyms/` automatically.** The
backend uses a Stripe idempotency key keyed on the gym id, so a
duplicate request for the *same* pending row is a no-op — but
the user clicks "create" once, and if the first attempt failed
before the 201, you want them to see the failure so they know
something went wrong.

## Expired `onboarding_url`

The hosted URL expires in ~5 minutes. Always check before
navigating:

```ts
function isExpired(expiresAtIso: string): boolean {
  const expiresAt = new Date(expiresAtIso).getTime();
  const SAFETY_MS = 10_000; // 10s safety margin
  return expiresAt - Date.now() < SAFETY_MS;
}
```

If expired on a `ResumeSetup` screen, call `GET /me/onboarding`
first to mint a fresh URL, then navigate.

If expired mid-onboarding (the user sat on a screen too long
and let the URL die), Stripe will redirect to `refresh_url`
when they eventually click through. Your `/gym-setup/refresh`
route refetches `GET /me/onboarding`, gets a fresh URL, and
navigates them back to Stripe — same pattern as `ResumeSetup`.

## Tab visibility during onboarding

The poller pauses while the tab is hidden (see `03_polling.md`).
When the tab becomes visible again, the poller fires an
immediate `GET /me/onboarding` before resuming its normal
cadence. Rationale:

- The user likely opened Stripe in a new tab and switched to it.
  The main tab was hidden for the duration of the hosted flow.
- When they tab back, they want an immediate answer, not a
  10-second wait.
- Stripe's own `account.updated` webhook will probably have
  already landed in the DB by the time they tab back, so the
  first post-visibility fetch often lands on `complete` or
  `disabled` without needing another tick.

The cost of an immediate refetch is one cheap backend call plus
one Stripe round-trip. The cost of trusting stale local state
is a confused user.

## "What NOT to do" list

- **Do not write to `gyms` or `gym_employees` via the Supabase
  JS client.** INSERT/UPDATE have been revoked at the database
  level. The call will return an RLS error no matter what. If
  you need to make a change to a gym row, add a backend
  endpoint for it.
- **Do not store the `onboarding_url`** past one use. It is a
  single-use, ~5-minute hosted link. Keep it in component /
  route state only, never in `localStorage` / `sessionStorage`
  / IndexedDB.
- **Do not parse `disabled_reason`.** Pass it through verbatim
  to support / error UI. It is an opaque Stripe string and may
  change without warning.
- **Do not parse `requirements_currently_due`.** Same rule.
  Display items verbatim if you need to show them at all.
- **Do not cache `stripe_onboarding_status` across app launches.**
  Always re-fetch via `GET /api/v1/gyms/me/onboarding` on app
  start during the setup flow. The backend is driven by Stripe
  webhooks that can flip the status at any time.
- **Do not assume `return_url` means `complete`.** Always
  re-fetch status and let the backend tell you. The user may
  have partially completed the hosted flow and been redirected
  back anyway. The poller is the source of truth — the
  `/gym-setup/return` route is just a place to host the
  "verifying..." UI.
- **Do not retry `POST /api/v1/gyms/` automatically** on a 5xx.
  Let the user see the error and click retry manually.
- **Do not try to read the gym row via
  `supabase.from('gyms').select()` during setup.** The filtered
  view hides pending rows, so you will see nothing even when
  the gym exists.
- **Do not hardcode the Stripe connect URL anywhere.** The
  backend returns it. If the backend returns a null
  `onboarding_url` (on `complete` / `disabled`), respect that
  and do not construct one yourself.
- **Do not show "loading" forever while waiting for a webhook.**
  The frontend should never block on webhook delivery. The
  poller calls `GET /me/onboarding`, which is a synchronous
  read against Stripe — the webhook is a parallel sync path
  the frontend never waits on directly.

## Debug / dev escape hatches

During development you will want a way to wipe local state and
re-test the happy path without going through Stripe every time.
Options:

- Have support (or a direct psql session) nuke the pending gym
  row. Use `DELETE FROM gyms_unfiltered WHERE gym_id = ...`
  and `DELETE FROM gym_employees WHERE gym_id = ...` in that
  order. Do not do this against production.
- Log out / log in as a new Supabase user. Each user owns at
  most one gym, so switching users gives you a fresh slate.

There is no backend "reset my gym" endpoint by design — gym
creation is a one-shot, audit-worthy operation.
